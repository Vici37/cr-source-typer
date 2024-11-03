class SourceTyper
  getter program

  def initialize(@entrypoint : String, @filenames : Array(String), @use_prelude : Bool)
    @entrypoint = File.expand_path(@entrypoint) unless @entrypoint.starts_with?("/")
    @program = Crystal::Program.new
  end

  def run : Hash(String, String)
    parser = program.new_parser(File.read(@entrypoint))
    parser.filename = @entrypoint
    parser.wants_doc = false
    original_node = parser.parse

    nodes = Crystal::Expressions.from([original_node])

    if @use_prelude
      # Prepend the prelude to the parsed program
      location = Crystal::Location.new(@entrypoint, 1, 1)
      nodes = Crystal::Expressions.new([Crystal::Require.new("prelude").at(location), nodes] of Crystal::ASTNode)
    end

    # And normalize
    program.normalize(nodes)

    # And now infer types of everything
    semantic_node = program.semantic nodes, cleanup: true
    def_visitor = DefVisitor.new(@filenames)
    semantic_node.accept(def_visitor)

    def_id_to_hash = def_visitor.all_defs.map { |d| {d.object_id, d.hash} }.to_h
    init_signatures(def_id_to_hash)

    if def_visitor.files.empty?
      return {} of String => String
    end

    rets = {} of String => String
    def_visitor.files.each do |file|
      next unless File.file?(file)
      formatter = SourceTyperFormatter.new(file, signatures)

      parser = program.new_parser(File.read(file))
      parser.filename = file
      parser.wants_doc = false
      original_node = parser.parse

      formatter.skip_space_or_newline
      original_node.accept formatter
      rets[file] = formatter.finish if formatter.added_types?
    end
    rets
  end

  # If a def is already fully typed, we don't need to check / write it
  private def fully_typed?(d : Def) : Bool
    ret = true
    ret &= d.args.all?(&.restriction)
    ret &= !!d.return_type
    ret
  end

  @_signatures : Hash(String, Signature)?

  # Creates a mapping of (parsed) def.object_id => Signature . A parsed def might not have a Signature
  # if it's not used, and therefore isn't typed
  private def signatures : Hash(String, Signature)
    @_signatures || raise "Signatures not properly initialized!"
  end

  # Generates a map of Def#hash => Signature for that Def
  private def init_signatures(def_id_to_hash : Hash(UInt64, UInt64)) : Hash(String, Signature)
    def_id_to_def_instances = Hash(UInt64, Array(Crystal::Def)).new { |h, k| h[k] = [] of Crystal::Def }

    program.def_instances.each do |instance_key, def_instance|
      next unless def_id_to_hash.keys.includes?(instance_key.def_object_id)

      def_id_to_def_instances[instance_key.def_object_id] << def_instance
    end

    types = [] of Crystal::Type

    program.types.each { |_, t| types << t }

    while type = types.shift?
      type.types?.try &.each { |_, t| types << t }
      if type.responds_to?(:def_instances)
        type.def_instances.each do |instance_key, def_instance|
          next unless def_id_to_hash.keys.includes?(instance_key.def_object_id)

          def_id_to_def_instances[instance_key.def_object_id] << def_instance
        end
      end
    end

    # This is hard to read, but transforms the def_instances hash into a hash of def_object_id -> its full Signature
    @_signatures ||= def_id_to_def_instances.compact_map do |def_id, def_instances|
      # Finally, combine all def_instances for a single def_obj_id into a single signature

      # If there's no location, there's nothing to re-write
      next nil if def_instances[0].location.nil?

      # Resolve all method arguments for this def into a hash of String -> ASTNode (where it will be a single type, or a union type)
      all_args = def_instances.map(&.args.map do |arg|
        t = arg.type
        {arg.name, t.is_a?(Crystal::VirtualType) ? t.base_type : t}
      end.reduce({} of String => Crystal::Type) do |acc, n|
        acc[n[0]] = n[1]
        acc
      end).reduce(Hash(String, Set(Crystal::Type)).new { |h, k| h[k] = Set(Crystal::Type).new }) do |acc, n|
        n.each do |name, type|
          acc[name] << type
        end
        acc
      end.map do |name, type_set|
        if type_set.size > 1
          {name, Crystal::Union.new(type_set.map { |t| Crystal::Var.new(t.to_s).as(Crystal::ASTNode) })}
        else
          {name, Crystal::Var.new(type_set.to_a[0].to_s)}
        end
      end.to_h

      # Similar idea for return_type
      returns = def_instances.compact_map(&.type).uniq!

      return_type = if returns.size > 1
                      Crystal::Union.new(returns.map { |t| Crystal::Var.new(t.to_s).as(Crystal::ASTNode) })
                    else
                      Crystal::Var.new(returns[0].to_s)
                    end

      {def_instances[0].location.to_s, Signature.new(
        name: def_instances[0].name,
        def_object_id: def_id,
        return_type: return_type,
        location: def_instances[0].location.not_nil!,
        args: all_args
      )}
    end.to_h
  end
end

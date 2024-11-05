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

    accepted_def_ids = def_visitor.all_defs.map(&.object_id)
    init_signatures(accepted_def_ids)

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

  # Return all def_instances that map to an accepted def object_id. A given def can have multiple
  # def_instances when called with different argument types.
  private def accepted_def_instances(accepted_def_ids : Array(UInt64)) : Array(Array(Crystal::Def))
    ret = Hash(UInt64, Array(Crystal::Def)).new { |h, k| h[k] = [] of Crystal::Def }

    program.def_instances.each do |instance_key, def_instance|
      next unless accepted_def_ids.includes?(instance_key.def_object_id)

      ret[instance_key.def_object_id] << def_instance
    end

    types = [] of Crystal::Type

    program.types.each { |_, t| types << t }

    while type = types.shift?
      type.types?.try &.each { |_, t| types << t }

      if type.responds_to?(:def_instances)
        type.def_instances.each do |instance_key, def_instance|
          next unless accepted_def_ids.includes?(instance_key.def_object_id)

          ret[instance_key.def_object_id] << def_instance
        end
      end

      metaclass = type.metaclass
      if metaclass.responds_to?(:def_instances)
        metaclass.def_instances.each do |instance_key, def_instance|
          next unless accepted_def_ids.includes?(instance_key.def_object_id)

          ret[instance_key.def_object_id] << def_instance
        end
      end
    end

    ret.values
  end

  # Generates a map of Def#hash => Signature for that Def
  private def init_signatures(accepted_def_ids : Array(UInt64)) : Hash(String, Signature)
    # This is hard to read, but transforms the def_instances array into a hash of def.location -> its full Signature
    @_signatures ||= accepted_def_instances(accepted_def_ids).compact_map do |def_instances|
      # Finally, combine all def_instances for a single def_obj_id into a single signature

      # If there's no location, there's nothing to re-write
      next nil if def_instances[0].location.nil?

      # Resolve all method arguments for this def into a hash of String -> ASTNode (where it will be a single type, or a union type)
      all_args = def_instances.map do |def_instance|
        arg_types = {} of String => Crystal::Type

        def_instance.args.each do |arg|
          t = arg.type
          arg_types[arg.name] = t.is_a?(Crystal::VirtualType) ? t.base_type : t
        end

        if arg = def_instance.block_arg
          t = arg.type
          arg_types[arg.name] = t.is_a?(Crystal::VirtualType) ? t.base_type : t
        end

        arg_types
      end.reduce(Hash(String, Set(Crystal::Type)).new { |h, k| h[k] = Set(Crystal::Type).new }) do |acc, def_args|
        def_args.each do |name, arg_type|
          acc[name] << arg_type
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
        return_type: return_type,
        location: def_instances[0].location.not_nil!,
        args: all_args
      )}
    end.to_h
  end
end

class SourceTyper
  getter program

  def initialize(@entrypoint : String, @def_locators : Array(String), @options : CliOptions)
    @entrypoint = File.expand_path(@entrypoint) unless @entrypoint.starts_with?("/")
    @program = Crystal::Program.new
  end

  def run : Hash(String, String)
    parser = program.new_parser(File.read(@entrypoint))
    parser.filename = @entrypoint
    parser.wants_doc = false
    original_node = parser.parse

    nodes = Crystal::Expressions.from([original_node])

    if @options.use_prelude?
      # Prepend the prelude to the parsed program
      location = Crystal::Location.new(@entrypoint, 1, 1)
      nodes = Crystal::Expressions.new([Crystal::Require.new("prelude").at(location), nodes] of Crystal::ASTNode)
    end

    # And normalize
    program.normalize(nodes)

    # And now infer types of everything
    semantic_node = program.semantic nodes, cleanup: true
    def_visitor = DefVisitor.new(@def_locators)
    semantic_node.accept(def_visitor)

    accepted_def_locations = def_visitor.all_defs.map(&.location.to_s).uniq!
    accepted_defs = def_visitor.all_defs.map do |the_def|
      {
        the_def.location.to_s,
        the_def,
      }
    end.to_h
    init_signatures(accepted_defs)

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
  private def accepted_def_instances(accepted_defs : Hash(String, Crystal::Def)) : Hash(String, Array(Crystal::Def))
    ret = Hash(String, Array(Crystal::Def)).new do |h, k|
      h[k] = [] of Crystal::Def
    end

    program.def_instances.each do |_, def_instance|
      next unless accepted_defs.keys.includes?(def_instance.location.to_s)

      ret[def_instance.location.to_s] << def_instance
    end

    types = [] of Crystal::Type

    program.types.each { |_, t| types << t }

    while type = types.shift?
      type.types?.try &.each { |_, t| types << t }

      if type.responds_to?(:def_instances)
        type.def_instances.each do |_, def_instance|
          next unless accepted_defs.keys.includes?(def_instance.location.to_s)

          ret[def_instance.location.to_s] << def_instance
        end
      end

      metaclass = type.metaclass
      if metaclass.responds_to?(:def_instances)
        metaclass.def_instances.each do |_, def_instance|
          next unless accepted_defs.keys.includes?(def_instance.location.to_s)

          ret[def_instance.location.to_s] << def_instance
        end
      end
    end

    ret
  end

  private def resolve_type(arg)
    t = arg.type
    t.is_a?(Crystal::VirtualType) ? t.base_type : t
  end

  # Generates a map of Def#location => Signature for that Def
  private def init_signatures(accepted_defs : Hash(String, Crystal::Def)) : Hash(String, Signature)
    # This is hard to read, but transforms the def_instances array into a hash of def.location -> its full Signature
    @_signatures ||= accepted_def_instances(accepted_defs).compact_map do |location, def_instances|
      # Finally, combine all def_instances for a single def_obj_id into a single signature

      parsed = accepted_defs[location]

      all_typed_args = Hash(String, Set(Crystal::Type)).new { |h, k| h[k] = Set(Crystal::Type).new }
      safe_splat_index = parsed.splat_index || Int32::MAX
      splat_arg_name = parsed.args[safe_splat_index]?.try &.name
      named_arg_name = parsed.double_splat.try &.name

      encountered_non_splat_arg_def_instance = false
      encountered_non_double_splat_arg_def_instance = false

      def_instances.each do |def_instance|
        encountered_splat_arg = false
        encountered_double_splat_arg = false
        def_instance.args.each do |arg|
          if arg.name == arg.external_name && !arg.name.starts_with?("__temp_")
            all_typed_args[arg.external_name] << resolve_type(arg)
          elsif @options.type_splats? && (splat_arg = splat_arg_name) && arg.name == arg.external_name && arg.name.starts_with?("__temp_")
            encountered_splat_arg = true
            all_typed_args[splat_arg] << resolve_type(arg)
          elsif @options.type_double_splats? && (named_arg = named_arg_name) && arg.name != arg.external_name && arg.name.starts_with?("__temp_")
            encountered_double_splat_arg = true
            all_typed_args[named_arg] << resolve_type(arg)
          elsif (!@options.type_splats? || !@options.type_double_splats?) && arg.name.starts_with?("__temp_")
            # Ignore, it didn't fall into one of the above conditions
          else
            raise "Unknown handling of arg #{arg} in #{def_instance}\n#{parsed}"
          end
        end

        encountered_non_splat_arg_def_instance |= !encountered_splat_arg
        encountered_non_double_splat_arg_def_instance |= !encountered_double_splat_arg

        if @options.type_blocks? && (arg = def_instance.block_arg)
          all_typed_args[arg.external_name] << resolve_type(arg)
        end
      end

      # If a given collection of def_instances has a splat defined AND at least one def_instance didn't have a type for it,
      # then we can't add types to the signature.
      # https://crystal-lang.org/reference/1.14/syntax_and_semantics/type_restrictions.html#splat-type-restrictions
      if @options.type_splats? && (splat_arg = splat_arg_name) && encountered_non_splat_arg_def_instance
        puts "WARNING: not adding type restriction for splat, found empty splat call: #{parsed.location}"
        all_typed_args.delete(splat_arg)
      end
      if @options.type_double_splats? && (named_arg = named_arg_name) && encountered_non_double_splat_arg_def_instance
        puts "WARNING: not adding type restriction for double splat, found empty deouble splat call: #{parsed.location}"
        all_typed_args.delete(named_arg)
      end

      all_args = all_typed_args.map do |name, type_set|
        if type_set.size > 1
          {name, Crystal::Union.new(type_set.map { |t| Crystal::Var.new(t.to_s).as(Crystal::ASTNode) })}
        else
          {name, Crystal::Var.new(type_set.to_a[0].to_s)}
        end
      end.to_h

      # Similar idea for return_type
      returns = def_instances.compact_map do |inst|
        resolve_type(inst)
      end.uniq!

      return_type = if returns.size > 1
                      Crystal::Union.new(returns.map { |t| Crystal::Var.new(t.to_s).as(Crystal::ASTNode) })
                    else
                      Crystal::Var.new(returns[0].to_s)
                    end

      {parsed.location.to_s, Signature.new(
        name: parsed.name,
        return_type: return_type,
        location: parsed.location.not_nil!,
        args: all_args
      )}
    end.to_h
  end
end

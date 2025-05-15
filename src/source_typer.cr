class SourceTyper
  getter program, files

  def initialize(@entrypoint : String,
                 @def_locators : Array(String),
                 @excludes : Array(String),
                 @type_blocks : Bool,
                 @type_splats : Bool,
                 @type_double_splats : Bool,
                 @prelude : String = "prelude",
                 @union_size_threshold : Int32 = Int32::MAX,
                 @ignore_private_defs : Bool = false,
                 @ignore_protected_defs : Bool = false,
                 stats : Bool = false,
                 progress : Bool = false,
                 error_trace : Bool = false)
    @entrypoint = File.expand_path(@entrypoint) unless @entrypoint.starts_with?("/")
    @program = Crystal::Program.new
    @files = Set(String).new
    @warnings = [] of String

    @program.progress_tracker.stats = stats
    @program.progress_tracker.progress = progress
    @program.show_error_trace = error_trace
  end

  # Run the entire typing flow, from semantic to file reformatting
  def run : Hash(String, String)
    semantic(@entrypoint, File.read(@entrypoint))

    rets = {} of String => String

    @warnings.each do |warning|
      puts "WARNING: #{warning}"
    end

    @files.each do |file|
      next unless File.file?(file)
      source = File.read(file)
      if typed_source = type_source(file, source)
        rets[file] = typed_source
      end
    end

    rets
  end

  # Take the entrypoint file (and its textual content) and run semantic on it.
  # Semantic results are used to generate signatures for all defs that match
  # at least one def_locator.
  def semantic(entrypoint, entrypoint_content) : Nil
    parser = program.new_parser(entrypoint_content)
    parser.filename = entrypoint
    parser.wants_doc = false
    original_node = parser.parse

    nodes = Crystal::Expressions.from([original_node])

    if !@prelude.empty?
      # Prepend the prelude to the parsed program
      location = Crystal::Location.new(entrypoint, 1, 1)
      nodes = Crystal::Expressions.new([Crystal::Require.new(@prelude).at(location), nodes] of Crystal::ASTNode)
    end

    program.normalize(nodes)

    # And now infer types of everything
    semantic_node = program.semantic nodes, cleanup: true
    # puts "\nDone semantic" if @program.progress_tracker.progress

    # We might run semantic later in an attempt to resolve defaults, don't display those stats or progress
    @program.progress_tracker.stats = false
    @program.progress_tracker.progress = false

    # Use the DefVisitor to locate and match any 'def's that match a def_locator
    def_visitor = DefVisitor.new(@def_locators, @excludes, entrypoint, @ignore_private_defs, @ignore_protected_defs)
    semantic_node.accept(def_visitor)

    # Hash up the location => (parsed) definition.
    # At this point the types have been infeered (from semantic above) and stored in various
    # def_instances in the `program` arg and its types.
    accepted_defs = def_visitor.all_defs.map do |the_def|
      {
        the_def.location.to_s,
        the_def,
      }
    end.to_h
    init_signatures(accepted_defs)

    @files = def_visitor.files
  end

  # Given a (presumably) crystal file and its content, re-format it with the crystal-formatter-that-types-things (SourceTyperFormatter).
  # Returns nil if no type restrictions were added anywhere.
  def type_source(filename, source) : String?
    formatter = SourceTyperFormatter.new(source, signatures)

    parser = program.new_parser(source)
    parser.filename = filename
    parser.wants_doc = false
    original_node = parser.parse

    formatter.skip_space_or_newline
    original_node.accept formatter

    formatter.added_types? ? formatter.finish : nil
  end

  @_signatures : Hash(String, Signature)?

  # Signatures represents a mapping of location => Signature for def at that location
  def signatures : Hash(String, Signature)
    @_signatures || raise "Signatures not properly initialized!"
  end

  # Given `accepted_defs` (location => (parsed) defs that match a def_locator), generated a new hash of
  # location => (typed, multiple) def_instances that match a location.
  #
  # A given parsed def can have multiple def_instances, depending on how the method is called throughout
  # the program, and the types of those calls.
  private def accepted_def_instances(accepted_defs : Hash(String, Crystal::Def)) : Hash(String, Array(Crystal::Def))
    ret = Hash(String, Array(Crystal::Def)).new do |h, k|
      h[k] = [] of Crystal::Def
    end

    # First, check global definitions
    program.def_instances.each do |_, def_instance|
      next unless accepted_defs.keys.includes?(def_instance.location.to_s)

      ret[def_instance.location.to_s] << def_instance
    end

    # Breadth first search time! This list will be a continuously populated queue of all of the types we need
    # to scan, with newly discovered types added to the end of the queue from "parent" (namespace) types.
    types = [] of Crystal::Type

    program.types.each { |_, t| types << t }

    overridden_method_locations = {} of String => String
    while type = types.shift?
      type.types?.try &.each { |_, t| types << t }
      def_overrides_parent_def(type).each do |child_def_loc, ancestor_def_loc|
        overridden_method_locations[child_def_loc] = ancestor_def_loc
      end

      # Check for class instance 'def's
      if type.responds_to?(:def_instances)
        type.def_instances.each do |_, def_instance|
          next unless accepted_defs.keys.includes?(def_instance.location.to_s)

          ret[def_instance.location.to_s] << def_instance
        end
      end

      # Check for class 'self.def's
      metaclass = type.metaclass
      if metaclass.responds_to?(:def_instances)
        metaclass.def_instances.each do |_, def_instance|
          next unless accepted_defs.keys.includes?(def_instance.location.to_s)

          ret[def_instance.location.to_s] << def_instance
        end
      end
    end

    # Now remove all overridden methods
    overridden_method_locations.each do |child_loc, ancestor_loc|
      if ret.delete(child_loc)
        @warnings << "Not adding type restrictions to definition at #{child_loc} as it overrides definition #{ancestor_loc}"
      end
    end

    ret
  end

  private def def_overrides_parent_def(type) : Hash(String, String)
    overriden_locations = {} of String => String
    type.defs.try &.each_value do |defs_with_metadata|
      defs_with_metadata.each do |def_with_metadata|
        next if def_with_metadata.def.location.to_s.starts_with?("expanded macro:") || def_with_metadata.def.name == "initialize"
        type.ancestors.each do |ancestor|
          ancestor_defs_with_metadata = ancestor.defs.try &.[def_with_metadata.def.name]?
          ancestor_defs_with_metadata.try &.each do |ancestor_def_with_metadata|
            next if ancestor_def_with_metadata.def.location.to_s.starts_with?("expanded macro:")
            found_def_with_same_name = true

            if def_with_metadata.compare_strictness(ancestor_def_with_metadata, self_owner: type, other_owner: ancestor) == 0
              overriden_locations[def_with_metadata.def.location.to_s] = ancestor_def_with_metadata.def.location.to_s
              overriden_locations[ancestor_def_with_metadata.def.location.to_s] = def_with_metadata.def.location.to_s
            end
          end
        end
      end
    end
    overriden_locations
  end

  # Given an 'arg', return its type that's good for printing (VirtualTypes suffix themselves with a '+')
  private def resolve_type(arg)
    t = arg.type
    t.is_a?(Crystal::VirtualType) ? t.base_type : t
  end

  # Strip out any NoReturns, or Procs that point to them (maybe all generics? Start with procs)
  private def filter_no_return(types)
    compacted_types = types.to_a.reject! do |type|
      type.no_return? || (type.is_a?(Crystal::ProcInstanceType) && type.as(Crystal::ProcInstanceType).return_type.no_return?)
    end

    compacted_types << program.nil if compacted_types.empty?
    compacted_types
  end

  # Generates a map of (parsed) Def#location => Signature for that Def
  private def init_signatures(accepted_defs : Hash(String, Crystal::Def)) : Hash(String, Signature)
    @_signatures ||= accepted_def_instances(accepted_defs).compact_map do |location, def_instances|
      parsed = accepted_defs[location].as(Crystal::Def)

      all_typed_args = Hash(String, Set(Crystal::Type)).new { |h, k| h[k] = Set(Crystal::Type).new }

      # splats only exist in the parsed defs, while the def_instances have all had their splats "exploded".
      # For typing splats, use the parsed defs for splat names and scan def_intances for various arg names that look... splatty.
      safe_splat_index = parsed.splat_index || Int32::MAX
      splat_arg_name = parsed.args[safe_splat_index]?.try &.name.try { |name| name.empty? ? nil : name }
      named_arg_name = parsed.double_splat.try &.name

      encountered_non_splat_arg_def_instance = false
      encountered_non_double_splat_arg_def_instance = false

      def_instances.each do |def_instance|
        encountered_splat_arg = false
        encountered_double_splat_arg = false
        def_instance.args.each do |arg|
          if arg.name == arg.external_name && !arg.name.starts_with?("__temp_")
            # Regular arg
            all_typed_args[arg.external_name] << resolve_type(arg)
          elsif arg.name != arg.external_name && (arg.name.starts_with?("__arg") || !arg.name.starts_with?("__"))
            # Either
            # A class / instance var that used a keword and then got used in a method argument, like:
            # def begin=(@begin)
            # end
            # - OR -
            # A method used an external_name in the argument list, like:
            # def test(external_name real_name)
            # end
            all_typed_args[arg.external_name] << resolve_type(arg)
          elsif @type_splats && (splat_arg = splat_arg_name) && arg.name == arg.external_name && arg.name.starts_with?("__temp_")
            # Splat arg, where the compiler generated a uniq name for it
            encountered_splat_arg = true
            all_typed_args[splat_arg] << resolve_type(arg)
          elsif @type_double_splats && (named_arg = named_arg_name) && arg.name != arg.external_name && arg.name.starts_with?("__temp_")
            # Named splat arg, where an "external" name was retained, but compiler generated uniq name for it
            encountered_double_splat_arg = true
            all_typed_args[named_arg] << resolve_type(arg)
          elsif (!@type_splats || !@type_double_splats) && arg.name.starts_with?("__temp_")
            # Ignore, it didn't fall into one of the above conditions (i.e. typing a particular splat wasn't specified)
          else
            raise "Unknown handling of arg #{arg} at #{def_instance.location} in #{def_instance}\n#{parsed}"
          end
        end

        encountered_non_splat_arg_def_instance |= !encountered_splat_arg
        encountered_non_double_splat_arg_def_instance |= !encountered_double_splat_arg

        if @type_blocks && (arg = def_instance.block_arg)
          all_typed_args[arg.external_name] << resolve_type(arg)
        end
      end

      parsed.args.each do |arg|
        if def_val = arg.default_value
          if def_val.to_s.matches?(/^[A-Z_]+$/)
            # This looks like a constant, let's try qualifying it with the parent type
            def_val = Crystal::Path.new([parsed.owner.to_s, def_val.to_s])
          end
          all_typed_args[arg.external_name] << program.semantic(def_val).type rescue nil
        end
      end

      # If a given collection of def_instances has a splat defined AND at least one def_instance didn't have a type for it,
      # then we can't add types to the signature.
      # https://crystal-lang.org/reference/1.14/syntax_and_semantics/type_restrictions.html#splat-type-restrictions
      if @type_splats && (splat_arg = splat_arg_name) && encountered_non_splat_arg_def_instance
        @warnings << "Not adding type restriction for splat #{splat_arg}, found empty splat call: #{parsed.location}"
        all_typed_args.delete(splat_arg)
      end
      if @type_double_splats && (named_arg = named_arg_name) && encountered_non_double_splat_arg_def_instance
        @warnings << "Not adding type restriction for double splat #{named_arg}, found empty deouble splat call: #{parsed.location}"
        all_typed_args.delete(named_arg)
      end

      # Convert each set of types into a single ASTNode (for easier printing) representing those types
      all_args = all_typed_args.compact_map do |name, type_set|
        compacted_types = filter_no_return(type_set)

        {name, to_ast(compacted_types)}
      end.to_h

      # Similar idea for return_type to get into an easier to print state
      returns = filter_no_return(def_instances.compact_map do |inst|
        resolve_type(inst)
      end.uniq!)

      return_type = to_ast(returns)

      # Special case - if the method is a static 'new' method returning one thing, replace it with `self` (similar to skipping writing the return of `initialize` methods)
      return_type = if returns.size == 1 && parsed.receiver.to_s == "self" && parsed.name == "new"
                      returns = Crystal::Var.new("self")
                    else
                      to_ast(returns)
                    end

      {parsed.location.to_s, Signature.new(
        name: parsed.name,
        return_type: return_type,
        location: parsed.location.not_nil!,
        args: all_args
      )}
    end.to_h
  end

  # Given a list of types, wrap them in a ASTNode appropriate for printing that type out
  private def to_ast(types : Array(Crystal::Type)) : Crystal::ASTNode?
    flattened = flatten_types(types)
    return nil if flattened.size > @union_size_threshold
    case flattened.size
    when 1
      # Use var to communicate a single type name
      Crystal::Var.new(type_name(flattened[0]))
    when 2
      if flattened.includes?(program.nil)
        # One type is Nil, so write this using the slightly more human readable format with a '?' suffix
        not_nil_type = flattened.reject(&.==(program.nil))[0]
        Crystal::Var.new("#{not_nil_type}?")
      else
        Crystal::Union.new(flattened.map { |t| Crystal::Var.new(type_name(t)).as(Crystal::ASTNode) })
      end
    else
      Crystal::Union.new(flattened.map { |t| Crystal::Var.new(type_name(t)).as(Crystal::ASTNode) })
    end
  end

  def flatten_types(types : Array(Crystal::Type)) : Array(Crystal::Type)
    types.map do |type|
      type.is_a?(Crystal::UnionType) ? flatten_types(type.concrete_types) : type
    end.flatten.uniq!
  end

  def type_name(type : Crystal::Type) : String
    type.to_s.gsub(/:Module\b/, ".class").gsub("+", "")
  end
end

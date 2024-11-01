module Crystal
  class SourceTyper
    # Represents a fully typed definition signature
    record Signature,
      name : String,
      def_object_id : UInt64,
      return_type : ASTNode,
      location : Crystal::Location,
      # TODO
      block_arg : String? = nil,
      args = {} of String => ASTNode

    getter program

    def initialize(@entrypoint : String, @filenames : Array(String))
      @program = Program.new
    end

    def run : Hash(String, String)
      parser = program.new_parser(File.read(@entrypoint))
      parser.filename = @entrypoint
      parser.wants_doc = false
      original_node = parser.parse

      nodes = Expressions.from([original_node])

      # Prepend the prelude to the parsed program
      location = Location.new(@entrypoint, 1, 1)
      nodes = Expressions.new([Require.new("prelude").at(location), nodes] of ASTNode)

      # And normalize
      program.normalize(nodes)

      # And now infer types of everything
      semantic_node = program.semantic nodes, cleanup: true
      def_visitor = DefVisitor.new(@filenames)
      semantic_node.accept(def_visitor)

      def_id_to_hash = def_visitor.all_defs.map { |d| {d.object_id, d.hash} }.to_h
      pp! def_id_to_hash
      init_signatures(def_id_to_hash)
      pp! signatures

      pp! def_visitor.files
      if def_visitor.files.empty?
        puts "Nothing to type"
        return {} of String => String
      end

      rets = {} of String => String
      def_visitor.files.each do |file|
        next unless File.file?(file)
        pp! file
        formatter = SourceTyperFormatter.new(file, def_visitor.accepted_locators, signatures)

        parser = program.new_parser(File.read(file))
        parser.filename = file
        parser.wants_doc = false
        original_node = parser.parse

        formatter.skip_space_or_newline
        original_node.accept formatter
        rets[file] = formatter.finish
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

    @_signatures : Hash(UInt64, Signature)?

    # Creates a mapping of (parsed) def.object_id => Signature . A parsed def might not have a Signature
    # if it's not used, and therefore isn't typed
    private def signatures : Hash(UInt64, Signature)
      @_signatures || raise "Signatures not properly initialized!"
    end

    # Generates a map of Def#hash => Signature for that Def
    private def init_signatures(def_id_to_hash : Hash(UInt64, UInt64))
      def_id_to_def_instances = Hash(UInt64, Array(Def)).new { |h, k| h[k] = [] of Def }

      program.def_instances.each do |instance_key, def_instance|
        next unless def_id_to_hash.keys.includes?(instance_key.def_object_id)

        def_id_to_def_instances[instance_key.def_object_id] << def_instance
      end

      types = [] of Crystal::Type

      program.types.each { |_, t| types << t }

      while type = types.shift?
        type.types.each { |_, t| types << t }
        pp! type
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
          {arg.name, arg.type}
        end.reduce({} of String => Type) do |acc, n|
          acc[n[0]] = n[1]
          acc
        end).reduce(Hash(String, Set(Type)).new { |h, k| h[k] = Set(Type).new }) do |acc, n|
          n.each do |name, type|
            acc[name] << type
          end
          acc
        end.map do |name, type_set|
          if type_set.size > 1
            {name, Union.new(type_set.map { |t| Var.new(t.to_s).as(ASTNode) })}
          else
            {name, Var.new(type_set.to_a[0].to_s)}
          end
        end.to_h

        # Similar idea for return_type
        returns = def_instances.compact_map(&.type).uniq!

        return_type = if returns.size > 1
                        Union.new(returns.map { |t| Var.new(t.to_s).as(ASTNode) })
                      else
                        Var.new(returns[0].to_s)
                      end

        {def_id_to_hash[def_id], Signature.new(
          name: def_instances[0].name,
          def_object_id: def_id,
          return_type: return_type,
          location: def_instances[0].location.not_nil!,
          args: all_args
        )}
      end.to_h
    end

    # Visitor for recording all Defs
    class DefVisitor < Visitor
      getter all_defs = Array(Def).new
      getter files = Set(String).new
      getter accepted_locators = Set(Crystal::Location).new

      @file_locators : Array(String)
      @line_locators : Array(String)
      @line_and_column_locators : Array(String)

      def initialize(@def_locators : Array(String))
        # TODO: support directories
        @file_locators = @def_locators.select { |d| d.count(":") == 0 }
        @line_locators = @def_locators.select { |d| d.count(":") == 1 }
        @line_and_column_locators = @def_locators.select { |d| d.count(":") == 2 }
      end

      def visit(node : Def)
        return unless loc = node.location
        return unless loc.filename && loc.line_number && loc.column_number
        if node_in_def_locators(loc)
          accepted_locators << loc
          all_defs << node
          files << loc.filename.to_s
        end

        false
      end

      def visit(node : ASTNode)
        true
      end

      private def node_in_def_locators(location : Location) : Bool
        return true if @def_locators.empty?
        return true if @file_locators.includes?(location.filename)
        return true if @line_locators.includes?("#{location.filename}:#{location.line_number}")
        @line_and_column_locators.includes?("#{location.filename}:#{location.line_number}:#{location.column_number}")
      end
    end

    class SourceTyperFormatter < Crystal::Formatter
      @current_def : Def? = nil

      def initialize(filename, @accepted_locators : Set(Crystal::Location), @signatures : Hash(UInt64, Signature))
        source = File.read(filename)
        pp! source
        @lexer = Lexer.new(source)
        @lexer.comments_enabled = true
        @lexer.count_whitespace = true
        @lexer.wants_raw = true
        @comment_columns = [nil] of Int32?
        @indent = 0
        @line = 0
        @column = 0
        @token = @lexer.next_token

        @output = IO::Memory.new(source.bytesize)
        @line_output = IO::Memory.new
        @wrote_newline = false
        @wrote_double_newlines = false
        @wrote_comment = false
        @macro_state = Token::MacroState.default
        @inside_macro = 0
        @inside_cond = 0
        @inside_lib = 0
        @inside_enum = 0
        @inside_struct_or_union = 0
        @implicit_exception_handler_indent = 0
        @last_write = ""
        @exp_needs_indent = true
        @inside_def = 0

        # When we parse a type, parentheses information is not stored in ASTs, unlike
        # for an Expressions node. So when we are printing a type (Path, ProcNotation, Union, etc.)
        # we increment this when we find a '(', and decrement it when we find ')', but
        # only if `paren_count > 0`: it might be the case of `def foo(x : A)`, but we don't
        # want to print that last ')' when printing the type A.
        @paren_count = 0

        # This stores the column number (if any) of each comment in every line
        @when_infos = [] of AlignInfo
        @hash_infos = [] of AlignInfo
        @assign_infos = [] of AlignInfo
        @doc_comments = [] of CommentInfo
        @current_doc_comment = nil
        @hash_in_same_line = Set(ASTNode).new.compare_by_identity
        @shebang = @token.type.comment? && @token.value.to_s.starts_with?("#!")
        @heredoc_fixes = [] of HeredocFix
        @last_is_heredoc = false
        @last_arg_is_skip = false
        @string_continuation = 0
        @inside_call_or_assign = 0
        @passed_backslash_newline = false

        # Lines that must not be rstripped (HEREDOC lines)
        @no_rstrip_lines = Set(Int32).new

        # Variables for when we format macro code without interpolation
        @vars = [Set(String).new]
      end

      def visit(node : Def)
        puts "In def: #{node} #{node.hash}"
        @implicit_exception_handler_indent = @indent
        @inside_def += 1
        @vars.push Set(String).new

        write_keyword :abstract, " " if node.abstract?

        write_keyword :def, " ", skip_space_or_newline: false

        if receiver = node.receiver
          skip_space_or_newline
          accept receiver
          skip_space_or_newline
          write_token :OP_PERIOD
        end

        @lexer.wants_def_or_macro_name do
          skip_space_or_newline
        end

        write node.name

        indent do
          next_token

          # this formats `def foo # ...` to `def foo(&) # ...` for yielding
          # methods before consuming the comment line
          if node.block_arity && node.args.empty? && !node.block_arg && !node.double_splat
            write "(&)"
          end

          skip_space consume_newline: false
          next_token_skip_space if @token.type.op_eq?
        end

        @current_def = node
        to_skip = format_def_args node
        @current_def = nil

        if return_type = node.return_type
          skip_space
          write_token " ", :OP_COLON, " "
          skip_space_or_newline
          accept return_type
        elsif @accepted_locators.includes?(node.location) && (sig = @signatures[node.hash]?)
          skip_space
          write " : #{sig.return_type.to_s}"
          skip_space_or_newline
        end

        if free_vars = node.free_vars
          skip_space_or_newline
          write " forall "
          next_token
          last_index = free_vars.size - 1
          free_vars.each_with_index do |free_var, i|
            skip_space_or_newline
            check :CONST
            write free_var
            next_token
            skip_space_or_newline if last_index != i
            if @token.type.op_comma?
              write ", "
              next_token_skip_space_or_newline
            end
          end
        end

        body = remove_to_skip node, to_skip

        unless node.abstract?
          format_nested_with_end body
        end

        @vars.pop
        @inside_def -= 1

        false
      end

      def visit(node : Arg)
        @last_arg_is_skip = false

        restriction = node.restriction
        default_value = node.default_value

        if @inside_lib > 0
          # This is the case of `fun foo(Char)`
          if !@token.type.ident? && restriction
            accept restriction
            return false
          end
        end

        if node.name.empty?
          skip_space_or_newline
        else
          @vars.last.add(node.name)

          at_skip = at_skip?

          if !at_skip && node.external_name != node.name
            if node.external_name.empty?
              write "_"
            elsif @token.type.delimiter_start?
              accept StringLiteral.new(node.external_name)
            else
              write @token.value
            end
            write " "
            next_token_skip_space_or_newline
          end

          @last_arg_is_skip = at_skip?

          write @token.value
          next_token
        end

        if restriction
          skip_space_or_newline
          write_token " ", :OP_COLON, " "
          skip_space_or_newline
          accept restriction
        elsif @accepted_locators.includes?(@current_def.try &.location) && (sig = @signatures[@current_def.try &.object_id || 0_u64]?)
          skip_space_or_newline
          write " : #{sig.args[node.name].to_s}"
        end

        if default_value
          # The default value might be a Proc with args, so
          # we need to remember this and restore it later
          old_last_arg_is_skip = @last_arg_is_skip

          skip_space_or_newline

          check_align = check_assign_length node
          write_token " ", :OP_EQ, " "
          before_column = @column
          skip_space_or_newline
          accept default_value
          check_assign_align before_column, default_value if check_align

          @last_arg_is_skip = old_last_arg_is_skip
        end

        # This is the case of an enum member
        if @token.type.op_semicolon?
          next_token
          @lexer.skip_space
          if @token.type.comment?
            write_comment
            @exp_needs_indent = true
          else
            write ";" if @token.type.const?
            write " "
            @exp_needs_indent = @token.type.newline?
          end
        end

        false
      end
    end
  end
end

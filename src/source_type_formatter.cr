class SourceTyperFormatter < Crystal::Formatter
  @current_def : Crystal::Def? = nil

  def initialize(filename, @accepted_locators : Set(Crystal::Location), @signatures : Hash(String, Signature))
    source = File.read(filename)
    super(source)
  end

  def visit(node : Crystal::Def)
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
    elsif @accepted_locators.includes?(node.location) && (sig = @signatures[node.location.to_s]?) && sig.name != "initialize"
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

  def visit(node : Crystal::Arg)
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
          accept Crystal::StringLiteral.new(node.external_name)
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
    elsif @accepted_locators.includes?(@current_def.try &.location) && (sig = @signatures[@current_def.try &.location.to_s || 0_u64]?)
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

class DefVisitor < Crystal::Visitor
  getter all_defs = Array(Crystal::Def).new
  getter files = Set(String).new

  @dir_locators : Array(String)
  @file_locators : Array(String)
  @line_locators : Array(String)
  @line_and_column_locators : Array(String)

  def initialize(@def_locators : Array(String))
    if @def_locators.empty?
      # Nothing was provided, check if there's a 'src' directory and use that (to avoid trying to type the 'lib' directory)
      if File.directory?(File.expand_path("src"))
        @def_locators << File.expand_path("src")
      else
        # No idea where we are, use the current directory
        @def_locators << Dir.current
      end
    end

    def_locs = @def_locators.map { |p| File.expand_path(p) }
    @dir_locators = def_locs.reject(&.ends_with?(".cr")).select { |p| File.directory?(p) }
    @file_locators = def_locs.select(&.ends_with?(".cr")).select { |p| File.file?(p) }
    @line_locators = def_locs.select { |d| d.count(":") == 1 }
    @line_and_column_locators = def_locs.select { |d| d.count(":") == 2 }
  end

  def visit(node : Crystal::Def)
    return false unless loc = node.location
    return false unless File.exists?(loc.filename.to_s)
    return false unless loc.filename && loc.line_number && loc.column_number
    if node_in_def_locators(loc)
      all_defs << node
      files << loc.filename.to_s
    end

    false
  end

  def visit(node : Crystal::ASTNode)
    true
  end

  private def node_in_def_locators(location : Crystal::Location) : Bool
    return false unless location.to_s.starts_with?("/")
    return true if @dir_locators.any? { |d| location.filename.to_s.starts_with?(d) }
    return true if @file_locators.includes?(location.filename)
    return true if @line_locators.includes?("#{location.filename}:#{location.line_number}")
    @line_and_column_locators.includes?("#{location.filename}:#{location.line_number}:#{location.column_number}")
  end
end

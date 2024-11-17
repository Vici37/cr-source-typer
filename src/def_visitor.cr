class DefVisitor < Crystal::Visitor
  getter all_defs = Array(Crystal::Def).new
  getter files = Set(String).new

  @dir_locators : Array(String)
  @file_locators : Array(String)
  @line_locators : Array(String)
  @line_and_column_locators : Array(String)

  def initialize(@def_locators : Array(String), entrypoint)
    if @def_locators.empty?
      entrypoint_dir = File.dirname(entrypoint)
      # Nothing was provided, is the entrypoint in the `src` directory?
      if entrypoint_dir.ends_with?("/src") || entrypoint_dir.includes?("/src/")
        @def_locators << File.dirname(entrypoint_dir)
      else
        # entrypoint isn't in a 'src' directory, assume we should only type it, and only it, wherever it is
        @def_locators << entrypoint
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

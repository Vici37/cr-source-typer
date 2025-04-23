# A visitor for defs, oddly enough.
#
# Walk through the AST and capture all references to Defs that match a def_locator
class DefVisitor < Crystal::Visitor
  getter all_defs = Array(Crystal::Def).new
  getter files = Set(String).new

  CRYSTAL_LOCATOR_PARSER = /^.*\.cr(:(?<line_number>\d+))?(:(?<col_number>\d+))?$/

  @dir_locators : Array(String)
  @file_locators : Array(String) = [] of String
  @line_locators : Array(String) = [] of String
  @line_and_column_locators : Array(String) = [] of String
  @excludes : Array(String)

  def initialize(def_locators : Array(String), excludes : Array(String), entrypoint : String, @ignore_private_defs : Bool, @ignore_protected_defs : Bool)
    if def_locators.empty?
      # No def_locators provided, default to the directory of entrypoint.
      def_locators << File.dirname(entrypoint)
    end

    def_locs = def_locators.map { |p| File.expand_path(Crystal.normalize_path(p)) }
    @excludes = excludes.map { |p| File.expand_path(Crystal.normalize_path(p)) }
    @dir_locators = def_locs.reject(&.match(CRYSTAL_LOCATOR_PARSER))
    def_locs.compact_map(&.match(CRYSTAL_LOCATOR_PARSER)).each do |loc|
      @file_locators << loc[0] unless loc["line_number"]?
      @line_locators << loc[0] unless loc["col_number"]?
      @line_and_column_locators << loc[0] if loc["line_number"]? && loc["col_number"]?
    end

    @excludes = @excludes - @dir_locators
  end

  def visit(node : Crystal::Def)
    return false unless loc = node.location
    return false unless loc.filename && loc.line_number && loc.column_number
    return false if fully_typed?(node)
    return false if @ignore_private_defs && node.visibility.private?
    return false if @ignore_protected_defs && node.visibility.protected?
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
    # location isn't an actual filename (i.e. "expanded macro at ...")
    return false unless location.to_s.starts_with?("/") || location.to_s.starts_with?(/\w:/)

    # Location matched exactly
    return true if @line_and_column_locators.includes?("#{location.filename}:#{location.line_number}:#{location.column_number}")
    return true if @line_locators.includes?("#{location.filename}:#{location.line_number}")
    return true if @file_locators.includes?(location.filename)

    # Check excluded directories before included directories (this assumes excluded directories are children of included directories)
    return false if @excludes.any? { |d| location.filename.to_s.starts_with?(d) }

    return true if @dir_locators.any? { |d| location.filename.to_s.starts_with?(d) }

    # Whelp, nothing matched, skip this location
    false
  end

  # If a def is already fully typed, we don't need to check / write it
  private def fully_typed?(d : Crystal::Def) : Bool
    ret = true
    ret &= d.args.all?(&.restriction)
    ret &= (d.name == "initialize" || !!d.return_type)
    ret
  end
end

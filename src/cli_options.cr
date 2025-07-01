class CliOptions
  getter original_options : Array(String)
  getter entrypoint : String = ""
  getter def_locators : Array(String) = [] of String
  getter? use_prelude : Bool = true
  getter? type_blocks : Bool = false
  getter? type_splats : Bool = false
  getter? type_double_splats : Bool = false

  def initialize(@original_options : Array(String))
  end

  def parse : CliOptions
    options = @original_options.dup

    OptionParser.parse(options) do |opts|
      opts.banner = <<-USAGE
        Usage: typify [options] entrypoint [def_descriptor [def_descriptor [...]]]

        A def_descriptor comes in 4 formats:

        * A directory name ('src/')
        * A file ('src/my_project.cr')
        * A line number in a file ('src/my_project.cr:3')
        * The location of the def method to be typed, specifically ('src/my_project.cr:3:3')

        If a `def` definition matches a provided def_descriptor, then it will be typed if type restrictions are missing.
        If no dev_descriptors are provided, then 'src' is tried, or all files under current directory (and sub directories, recursive)
        are typed if no 'src' directory exists.

        Options:
        USAGE

      opts.on("-h", "--help", "Show this message") do
        puts opts
        exit
      end

      opts.on("--no-prelude", "Disable implicit prelude insertion") do
        @use_prelude = false
      end

      opts.on("--include-blocks", "Enable adding types to named block arguments (these usually get typed with Proc(Nil) and isn't helpful)") do
        @type_blocks = true
      end

      opts.on("--include-splats", "Enable adding types to splats") do
        @type_splats = true
      end

      opts.on("--include-double-splats", "Enable adding types to double splats") do
        @type_double_splats = true
      end
    end

    @entrypoint = options.shift
    @def_locators = options

    self
  end
end

require "prelude"
# require "compiler/requires"
require "compiler/crystal/annotatable"
require "compiler/crystal/program"
require "compiler/crystal/*"
require "compiler/crystal/semantic/*"
require "compiler/crystal/macros/*"

require "./ext/crystal_config"
require "./signature"
require "./def_visitor"
require "./source_type_formatter"
require "./source_typer"

options = ARGV.dup
OptionParser.parse(options) do |opts|
  opts.banner = <<-USAGE
        Usage: typer [options] entrypoint [def_descriptor [def_descriptor [...]]]

        A def_descriptor comes in 4 formats:

        * A directory name ('src/')
        * A file ('src/my_project.cr')
        * A line number in a file ('src/my_project.cr:3')
        * The location of the def method to be typed, specifically ('src/my_project.cr:3:3')

        If a `def` definition matches a provided def_descriptor, then it will be typed if type restrictions are missing

        Options:
        USAGE

  opts.on("-h", "--help", "Show this message") do
    puts opts
    exit
  end
end

entrypoint = options.shift

unless File.file?(entrypoint)
  puts "Entrypoint must be the crystal file you use to build your crystal project with"
  exit(1)
end

files = options

results = SourceTyper.new(entrypoint, files).run

results.each do |filename, file_contents|
  pp! filename, file_contents
  File.write(filename, file_contents)
end

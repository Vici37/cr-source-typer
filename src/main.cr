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
        Usage: crystal tool typer [options] [- | file or directory ...]

        Options:
        USAGE

  opts.on("-h", "--help", "Show this message") do
    puts opts
    exit
  end
end

entrypoint = options.shift
files = options

pp! entrypoint, files

results = SourceTyper.new(entrypoint, files).run
pp! results

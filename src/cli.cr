require "./requires"

use_prelude = true

cli_options = CliOptions.new(ARGV.dup).parse

unless File.file?(cli_options.entrypoint)
  puts "Entrypoint must be the crystal file you use to build your crystal project with"
  exit(1)
end

results = SourceTyper.new(
  cli_options.entrypoint,
  cli_options.def_locators,
  cli_options
).run

if results.empty?
  puts "No type restrictions added"
else
  results.each do |filename, file_contents|
    # pp! filename, file_contents
    File.write(filename, file_contents)
  end
end

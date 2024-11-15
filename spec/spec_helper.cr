require "spec"
require "../src/requires"

def new_program
  Crystal::Program.new
end

def parse(filename, source)
  parser = new_program.new_parser(source)
  parser.filename = filename
  parser.wants_doc = false
  parser.parse
end

def sample_spec(filename) : String
  "#{__DIR__}/sample_spec_files/#{filename}.cr"
end

def hello_world_filename : String
  sample_spec("hello_world")
end

def all_def_examples_filename : String
  sample_spec("all_def_examples")
end

def hello_world_content : String
  File.read(hello_world_filename)
end

def parse_hello_world
  filename = hello_world_filename
  parse(filename, hello_world_content)
end

def options(blocks : Bool, splats : Bool, double_splats : Bool, prelude : Bool = true) : CliOptions
  argv = [] of String
  argv << "--include-blocks" if blocks
  argv << "--include-splats" if splats
  argv << "--include-double-splats" if double_splats
  argv << "--no-prelude" unless prelude

  argv << "dummy"
  CliOptions.new(argv).parse
end

def signature(args : Hash(String, String), ret : String) : Signature
  Signature.new(
    "Name",
    Crystal::Var.new(ret),
    Crystal::Location.new("filename", 0, 0),
    args.map { |k, v| {k, Crystal::Var.new(v).as(Crystal::ASTNode)} }.to_h
  )
end

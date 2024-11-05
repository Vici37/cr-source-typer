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

def signature(args : Hash(String, String), ret : String) : Signature
  Signature.new(
    "Name",
    Crystal::Var.new(ret),
    Crystal::Location.new("filename", 0, 0),
    args.map { |k, v| {k, Crystal::Var.new(v).as(Crystal::ASTNode)} }.to_h
  )
end

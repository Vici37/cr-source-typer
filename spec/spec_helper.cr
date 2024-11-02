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

def hello_world_filename : String
  "#{__DIR__}/sample_spec_files/hello_world.cr"
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
    0_u64,
    Crystal::Var.new(ret),
    Crystal::Location.new("filename", 0, 0),
    nil,
    args.map { |k, v| {k, Crystal::Var.new(v).as(Crystal::ASTNode)} }.to_h
  )
end

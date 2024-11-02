require "./spec_helper"

describe SourceTyperFormatter do
  it "formats nothing" do
    formatter = SourceTyperFormatter.new(hello_world_filename, {} of String => Signature)
    node = parse_hello_world

    node.accept formatter

    formatter.added_types?.should be_false
    formatter.finish.should eq hello_world_content
  end

  it "Adds type information" do
    sig = signature({"world" => "String"}, "Nil")

    formatter = SourceTyperFormatter.new(hello_world_filename, {"#{hello_world_filename}:1:1" => sig})
    node = parse_hello_world

    node.accept formatter

    formatter.added_types?.should be_true
    formatter.finish.should eq <<-RESULT
    def hello(world : String) : Nil
    end

    def world
    end

    RESULT
  end
end

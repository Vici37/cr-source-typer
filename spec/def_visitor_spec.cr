require "./spec_helper"

describe DefVisitor do
  it "visits definitions and accepts file" do
    node = parse_hello_world
    visitor = DefVisitor.new([hello_world_filename], hello_world_filename)

    node.accept visitor

    visitor.files.to_a.should eq [hello_world_filename]
    visitor.all_defs.size.should eq 2
    visitor.all_defs[0].name.should eq "hello"
    visitor.all_defs[1].name.should eq "world"
  end

  it "visits line definitions and does nothing with non-def line" do
    node = parse_hello_world
    visitor = DefVisitor.new(["#{hello_world_filename}:2"], hello_world_filename)
    node.accept visitor
    visitor.files.should be_empty
  end

  it "visits line definitions and finds def" do
    node = parse_hello_world
    visitor = DefVisitor.new(["#{hello_world_filename}:1"], hello_world_filename)
    node.accept visitor
    visitor.files.to_a.should eq [hello_world_filename]
    visitor.all_defs.size.should eq 1
    visitor.all_defs[0].name.should eq "hello"
  end

  it "visits line definitions and finds different def" do
    node = parse_hello_world
    visitor = DefVisitor.new(["#{hello_world_filename}:4"], hello_world_filename)
    node.accept visitor
    visitor.files.to_a.should eq [hello_world_filename]
    visitor.all_defs.size.should eq 1
    visitor.all_defs[0].name.should eq "world"
  end

  it "visits line definitions and finds both" do
    node = parse_hello_world
    visitor = DefVisitor.new(["#{hello_world_filename}:4", "#{hello_world_filename}:1"], hello_world_filename)
    node.accept visitor
    visitor.files.to_a.should eq [hello_world_filename]
    visitor.all_defs.size.should eq 2
    visitor.all_defs[0].name.should eq "hello"
    visitor.all_defs[1].name.should eq "world"
  end

  it "visits character definitions and finds nothing" do
    node = parse_hello_world
    visitor = DefVisitor.new(["#{hello_world_filename}:1:2"], hello_world_filename)
    node.accept visitor
    visitor.files.should be_empty
  end

  it "visits character definitions and finds def" do
    node = parse_hello_world
    visitor = DefVisitor.new(["#{hello_world_filename}:1:1"], hello_world_filename)
    node.accept visitor
    visitor.files.to_a.should eq [hello_world_filename]
    visitor.all_defs.size.should eq 1
    visitor.all_defs[0].name.should eq "hello"
  end
end

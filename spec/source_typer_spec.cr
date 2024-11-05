require "./spec_helper"

describe SourceTyper do
  it "parses, runs semantic, and types everything" do
    entrypoint = all_def_examples_filename
    typer = SourceTyper.new(entrypoint, ["spec"], true, true)

    results = typer.run

    results.keys.should eq [entrypoint]
    results[entrypoint].should eq <<-RESULT
    # This file tries to capture each type of definition format
    def hello : String
      "world"
    end

    def hello1(arg1 : String) : String
      arg1
    end

    def hello2(arg1 : Int32, *, arg2 : Int32) : Int32
      arg1 + arg2
    end

    def hello3(&block : Proc(Nil)) : Nil
      block.call
    end

    class Test
      def hello : String
        "world"
      end

      def self.hello : String
        "world"
      end
    end

    hello
    hello1("world")
    hello2(1, arg2: 2)
    hello3 do
      "hello"
    end
    Test.hello
    Test.new.hello

    RESULT
  end

  it "parses, runs semantic, and types everything but named block params" do
    entrypoint = all_def_examples_filename
    typer = SourceTyper.new(entrypoint, ["spec"], true, false)

    results = typer.run

    results.keys.should eq [entrypoint]
    results[entrypoint].should eq <<-RESULT
    # This file tries to capture each type of definition format
    def hello : String
      "world"
    end

    def hello1(arg1 : String) : String
      arg1
    end

    def hello2(arg1 : Int32, *, arg2 : Int32) : Int32
      arg1 + arg2
    end

    def hello3(&block) : Nil
      block.call
    end

    class Test
      def hello : String
        "world"
      end

      def self.hello : String
        "world"
      end
    end

    hello
    hello1("world")
    hello2(1, arg2: 2)
    hello3 do
      "hello"
    end
    Test.hello
    Test.new.hello

    RESULT
  end
end

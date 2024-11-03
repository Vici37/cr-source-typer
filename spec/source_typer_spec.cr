require "./spec_helper"

describe SourceTyper do
  it "parses, runs semantic, and types everything" do
    entrypoint = all_def_examples_filename
    typer = SourceTyper.new(entrypoint, [] of String, true)

    results = typer.run

    results.keys.should eq [entrypoint]
    results[entrypoint].should eq <<-RESULT
    # This file tries to capture each type of definition format
    def hello : String
      "world"
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
    Test.hello
    Test.new.hello

    RESULT
  end
end

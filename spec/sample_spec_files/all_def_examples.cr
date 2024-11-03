# This file tries to capture each type of definition format
def hello
  "world"
end

class Test
  def hello
    "world"
  end

  def self.hello
    "world"
  end
end

hello
Test.hello
Test.new.hello

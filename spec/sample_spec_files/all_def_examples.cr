# This file tries to capture each type of definition format
def hello
  "world"
end

def hello1(arg1)
  arg1
end

def hello2(arg1, *, arg2)
  arg1 + arg2
end

def hello3(&block)
  block.call
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
hello1("world")
hello2(1, arg2: 2)
hello3 do
  "hello"
end
Test.hello
Test.new.hello

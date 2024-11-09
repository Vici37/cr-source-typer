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

def hello4(*args)
  args[0]?
end

def hello5(**args)
  nil
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
hello4(3, "ok")
hello5(test: "test", other: 3)
Test.hello
Test.new.hello

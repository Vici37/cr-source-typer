# Crystal Source Typer

This is a crystal tool that adds missing types to Crystal source code for `def` statements.

This tool is very much in alpha! Anything should be considered up for change, including the repository itself.

## Installation

Due to dependency on `llvm` in the semantic layer, LLVM 18+ will be needed to successfully build this tool. See [this](https://forum.crystal-lang.org/t/exploring-the-compiler/7343/8?u=tsornson) for details.

Add to your `shard.yml` file:

```
development_dependencies:
  source-typer:
    github: Vici37/cr-source-typer
```

And run shards install. A new build tool `bin/typer` should now exist.

## Usage

As always, you can always use the `-h` flag to get basic help instructions:

```
> ./bin/typer -h
```

When using it, the `typer` utility should be provided your entrypoint (the same crystal file used
with `crystal build`) and 0 or more definition locators, or places where you want typing added
if it's missing. Definition locators come in 4 "flavors":

* A directory name - all crystal code under that directory (recursive) will be typed
* A filename - all `def`s in that file will be typed
* A `filename:line_number` format - only add typing to the definition on this line
* A `filename:line_number:column_number` format - only add typing to a definition where the character `d` is on this line / column (unlikely to be used, but there it is)

Providing 0 definition locators is the same as providing either the 'src' directory (if it exists) or the current directory (if it doesn't). Trying to type the 'lib' directory can lead to a bad time.

Assume there's a local file `hello.cr` with contents:

```crystal
def hello(world)
  world
end

class Test
  def self.hello(world)
    0_u64
  end

  def hello
    "world"
  end
end

def i_am_not_called
  0
end

hello(37)
Test.hello("test")
Test.new.hello
```

Then running command `./typer hello.cr` will overwrite it with:

```crystal
def hello(world : Int32) : Int32
  world
end

class Test
  def self.hello(world : String) : UInt64
    0_u64
  end

  def hello : String
    "world"
  end
end

def i_am_not_called
  0
end

hello(37)
Test.hello("test")
Test.new.hello
```

**Note:** Only definitions that are called get typed. Unused methods won't be typed by crystal's semantic layer.

## Development

```
> git clone <this repo>
> cd <this repo>
> shards install
> make build
> make test
```

## Contributing

1. Fork it (<https://github.com/Vici37/cr-source-typer/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [Troy Sornson](https://github.com/Vici37) - creator and maintainer

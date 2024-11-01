module Crystal
  struct CrystalPath
    def self.default_paths : Array(String)
      prev = previous_def
      # Since the std lib isn't actually (likely) installed in the `lib` directory, we
      # need to find it and configure the program's crystal_path to look there, so that
      # the injected prelude will successfully compile. Use the crystal compiler itself
      # to find that :)
      io = IO::Memory.new
      Process.run("crystal", ["env"], output: io)
      cr_path = io.to_s
        .split("\n")
        .map(&.strip)
        .find!(&.starts_with?("CRYSTAL_PATH="))
        .split("=")[1]
        .split(":") # in case of `lib:path/to/crystal` format
        .find!(&.includes?("crystal/src"))

      prev + [cr_path]
    end
  end
end

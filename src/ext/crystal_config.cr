module Crystal
  struct CrystalPath
    CRYSTAL_ENV_PROPERTY = {{system("crystal env").stringify}}

    def self.default_paths : Array(String)
      # Since the std lib isn't actually (likely) installed in the `lib` directory, we
      # need to find it and configure the program's crystal_path to look there, so that
      # the injected prelude will successfully compile. Use the crystal compiler itself
      # to find that :)
      CRYSTAL_ENV_PROPERTY
        .split("\n")
        .map(&.strip)
        .find!(&.starts_with?("CRYSTAL_PATH="))
        .split("=")[1]
        .split(":") # in case of `lib:path/to/crystal` format
    end
  end
end

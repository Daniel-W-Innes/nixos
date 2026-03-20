_:

{
  services.borgmatic = {
    enable = true;
    settings = {
      source_directories = [
        "/home"
        "/etc"
        "/root"
        "/var"
        "/usr/local/bin"
        "/usr/local/sbin"
      ];

      repositories = [
        {
          path = "/run/media/daniel/stb/repo";
          label = "local";
        }
      ];

      exclude_patterns = [
        "/home/*/.cache"
        "*/steamapps"
      ];
      exclude_caches = true;

      compression = "zstd,7";
      recompress = "if-different";
      retries = 3;

      archive_name_format = "borgmatic_{hostname}_{now:%Y-%m-%dT%H:%M:%S.%f}";

      keep_daily = 7;
      keep_weekly = 4;
      keep_yearly = 1;

      checks = [
        {
          name = "archives";
          frequency = "1 days";
        }
        {
          name = "repository";
          frequency = "2 weeks";
        }
        # {
        #   name = "spot";
        #   count_tolerance_percentage = 0.1;
        #   data_sample_percentage = 5;
        #   data_tolerance_percentage = 1;
        #   frequency = "1 month";
        # }
      ];
    };
  };
}

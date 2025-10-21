{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    borgbackup
  ];
  services.borgmatic = {
    enable = true;
    enableConfigCheck = true;
    configurations."std" = {
      source_directories = [ "/home" "/etc" "/root" "/var" "/usr/local/bin" "/usr/local/sbin" ];
      repositories = [{ label = "std"; path = "/run/media/daniel/stb/repo"; }];
      exclude_patterns = [ "/home/*/.cache" "*/steamapps"];
      exclude_caches = true;
      compression = "zstd,7";
      recompress = "if-different";
      retries = 3;
      archive_name_format = "borgmatic_{hostname}_{now:%Y-%m-%dT%H:%M:%S.%f}";
      retention = {
        keep_within = "12H";
        keep_daily = 14;
        keep_weekly = 9;
        keep_monthly = 6;
        keep_yearly = 2;
      };
    };
  };
}

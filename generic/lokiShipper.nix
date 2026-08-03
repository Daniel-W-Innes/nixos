{
  config,
  lib,
  pkgs,
  secretsDir,
  ...
}:

{
  age.secrets.loki-shipper-password = {
    file = secretsDir + /loki-password.age;
    owner = "alloy";
    group = "alloy";
    mode = "0400";
  };

  services.alloy = {
    enable = true;
    configPath = builtins.toString (
      pkgs.writeText "alloy-config.alloy" ''
        logging {
          level  = "info"
          format = "logfmt"
        }

        loki.source.journal "journal" {
          format_as_json = true
          labels         = {"job" = "systemd-journal"}
          forward_to     = [loki.relabel.journal_labels.receiver]
        }

        loki.relabel "journal_labels" {
          forward_to = [loki.write.remote_loki.receiver]

          rule {
            source_labels = ["__journal__systemd_unit"]
            target_label  = "unit"
          }
          rule {
            source_labels = ["__journal__hostname"]
            target_label  = "hostname"
          }
          rule {
            source_labels = ["__journal_priority_keyword"]
            target_label  = "level"
          }
        }
      ''
      + (
        if config.virtualisation.oci-containers.backend == "docker" then
          ''
            loki.source.docker "docker" {
              forward_to = [loki.write.remote_loki.receiver]
              labels     = {
                "job"      = "docker",
                "hostname" = "${config.networking.hostName}",
              }
              host       = "unix:///var/run/docker.sock"
            }
          ''
        else if config.virtualisation.oci-containers.backend == "podman" then
          ''
            loki.source.docker "podman" {
              forward_to = [loki.write.remote_loki.receiver]
              labels     = {
                "job"      = "podman",
                "hostname" = "${config.networking.hostName}",
              }
              host       = "unix:///run/podman/podman.sock"
            }
          ''
        else
          ""
      )
      + ''
        loki.write "remote_loki" {
          endpoint {
            url = "https://loki.lc.brotherwolf.ca/loki/api/v1/push"
            basic_auth {
              username      = "admin"
              password_file = "${config.age.secrets.loki-shipper-password.path}"
            }
          }
          external_labels = {
            hostname = "${config.networking.hostName}",
          }
        }

        prometheus.exporter.self "alloy_self" {}
      ''
    );
  };

  systemd.services.alloy.serviceConfig.SupplementaryGroups = [ "systemd-journal" ];
}

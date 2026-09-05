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
    owner = "root";
    group = "root";
    mode = "0400";
  };

  systemd.services.alloy.serviceConfig = {
    LoadCredential = [
      "loki-shipper-password:${config.age.secrets.loki-shipper-password.path}"
    ];
    SupplementaryGroups = [ "systemd-journal" ];
  };

  services.alloy = {
    enable = true;
    configPath = builtins.toString (
      pkgs.writeText "alloy-config.alloy" ''
        logging {
          level  = "info"
          format = "logfmt"
        }

        loki.relabel "journal_rules" {
          forward_to = []

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

        loki.source.journal "journal" {
          format_as_json = true
          labels         = {"job" = "systemd-journal"}
          relabel_rules  = loki.relabel.journal_rules.rules
          forward_to     = [loki.write.remote_loki.receiver]
        }

        loki.source.docker "default" {
          forward_to = [loki.write.remote_loki.receiver]
          labels = {}
          host   = "unix:///run/podman/podman.sock"
          targets = []
        }

        loki.write "remote_loki" {
          endpoint {
            url = "https://loki.lc.brotherwolf.ca/loki/api/v1/push"
            basic_auth {
              username      = "admin"
              password_file = "/run/credentials/alloy.service/loki-shipper-password"
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
}

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
          forward_to     = [loki.process.journal_trim.receiver]
        }

        loki.process "journal_trim" {
          stage.json {
            expressions = {
              message      = "MESSAGE",
              priority     = "PRIORITY",
              syslog_id    = "SYSLOG_IDENTIFIER",
              unit_field   = "_SYSTEMD_UNIT",
              pid          = "_PID",
              uid          = "_UID",
              gid          = "_GID",
              comm         = "_COMM",
              transport    = "_TRANSPORT",
              container    = "CONTAINER_NAME",
              container_id = "CONTAINER_ID",
              code_file    = "CODE_FILE",
              code_func    = "CODE_FUNC",
              code_line    = "CODE_LINE",
            }
          }
          stage.template {
            source   = "trimmed"
            template = `{"MESSAGE":{{ toJson .message }},"PRIORITY":{{ toJson .priority }},"SYSLOG_IDENTIFIER":{{ toJson .syslog_id }},"_SYSTEMD_UNIT":{{ toJson .unit_field }},"_PID":{{ toJson .pid }},"_UID":{{ toJson .uid }},"_GID":{{ toJson .gid }},"_COMM":{{ toJson .comm }},"_TRANSPORT":{{ toJson .transport }},"CONTAINER_NAME":{{ toJson .container }},"CONTAINER_ID":{{ toJson .container_id }},"CODE_FILE":{{ toJson .code_file }},"CODE_FUNC":{{ toJson .code_func }},"CODE_LINE":{{ toJson .code_line }}}`
          }
          stage.output {
            source = "trimmed"
          }
          forward_to = [loki.write.remote_loki.receiver]
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

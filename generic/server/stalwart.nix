# Stalwart mail server (https://wiki.nixos.org/wiki/Stalwart), provisioned
# via the vendored post-26.11 module (modules/stalwart/, nixpkgs PR #552103)
# with the backported 1.x package (overlays/stalwart.nix).
#
# No TLS/DNS-01/ACME/DKIM yet: listeners are plaintext (SMTP 25, submission
# 587, IMAP 143 — LAN only) and the HTTP listener is loopback-only behind
# traefik. Certificate/DNS/DKIM management is pinned to Manual so Stalwart
# does not attempt any of it.
{
  config,
  pkgs,
  secretsDir,
  ...
}:

let
  variant = type: value: { "@type" = type; } // value;
in
{
  imports = [ ../../modules/stalwart ];

  age.secrets.stalwart-admin-password = {
    file = secretsDir + /stalwart-admin-password.age;
    # root-only; systemd LoadCredential reads it for stalwart.service.
    mode = "0400";
  };

  services.stalwart = {
    enable = true;
    package = pkgs.stalwart_1;
    stateVersion = "26.05";
    url = "https://stalwart.lc.brotherwolf.ca/";
    openFirewall = false;

    # Fallback admin, usable in recovery and production modes. The credential
    # key must match admin.username: stalwart-provision reads it with
    # `systemd-creds cat <username>`.
    admin = {
      enable = true;
      username = "stalwart-admin";
    };
    credentials."stalwart-admin" = config.age.secrets.stalwart-admin-password.path;

    # First bootstrap runs with recovery.enable = true (see
    # docs/debug/mail.md): stalwart starts with no mail listeners, serving
    # the management API on this port, and stalwart-provision applies the
    # whole plan below. Once it reports success, set this back to false and
    # switch again.
    recovery = {
      enable = false;
      port = 8088;
    };

    provision = {
      enable = true;
      # Served by the recovery listener during bootstrap and by the
      # provisioned `http` listener afterwards.
      urls = [ "http://127.0.0.1:8088" ];
      timeout = 300;

      singletons = {
        SystemSettings = {
          defaultHostname = "mail.brotherwolf.ca";
          defaultDomainId = "#brotherwolf";
          # Only traefik (loopback) may influence client-IP handling.
          proxyTrustedNetworks = [
            "127.0.0.1/32"
            "::1/128"
          ];
        };
        # Client IPs come from traefik's X-Forwarded-For; one trusted hop
        # (forwardedHops defaults to 1) and the HTTP listener is loopback.
        Http.clientIpSource = "xForwardedFor";
      };

      objects = {
        NetworkListener = {
          reconcile = true;
          match = [ "name" ];
          objects = {
            smtp = {
              name = "smtp";
              protocol = "smtp";
              bind = [ "[::]:25" ];
              useTls = false;
              implicitTls = false;
            };
            submission = {
              name = "submission";
              protocol = "smtp";
              bind = [ "[::]:587" ];
              useTls = false;
              implicitTls = false;
            };
            imap = {
              name = "imap";
              protocol = "imap";
              bind = [ "[::]:143" ];
              useTls = false;
              implicitTls = false;
            };
            http = {
              name = "http";
              protocol = "http";
              # Loopback only: traefik fronts it as
              # stalwart.lc.brotherwolf.ca.
              bind = [ "127.0.0.1:8088" ];
              useTls = false;
              implicitTls = false;
            };
          };
        };

        Domain = {
          reconcile = true;
          match = [ "name" ];
          objects.brotherwolf = {
            name = "brotherwolf.ca";
            # No ACME/DNS/DKIM automation until DNS-01 is set up.
            certificateManagement = variant "Manual" { };
            dnsManagement = variant "Manual" { };
            dkimManagement = variant "Manual" { };
          };
        };

        Account = {
          reconcile = true;
          match = [ "name" ];
          # No password is provisioned: PasswordCredential.secret is a plain
          # string and would end up in the Nix store. Set daniel's password
          # once via webadmin/stalwart-cli after bootstrap.
          objects.daniel = variant "User" {
            name = "daniel";
            domainId = "#brotherwolf";
          };
        };

        MtaMilter = {
          reconcile = true;
          match = [
            "host"
            "port"
          ];
          objects = {
            rspamd = {
              host = "127.0.0.1";
              port = 11332;
              useTls = false;
              stages = [
                "connect"
                "ehlo"
                "mail"
                "rcpt"
                "data"
              ];
            };
            clamav = {
              host = "127.0.0.1";
              port = 7357;
              useTls = false;
              stages = [ "data" ];
            };
          };
        };

        # Journal tracer so CrowdSec can tail stalwart's own auth events.
        Tracer = {
          reconcile = true;
          match = [ "@type" ];
          objects.journal = variant "Journal" {
            enable = true;
            level = "info";
          };
        };
      };
    };
  };

  # Mail ports for LAN clients only (no internet mail until MX/firewall work).
  # ens3 is melon's NIC (facter).
  networking.firewall.interfaces."ens3".allowedTCPPorts = [
    25
    587
    143
  ];
}

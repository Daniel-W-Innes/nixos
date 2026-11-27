# ClamAV scans mail through clamav-milter (Stalwart has no built-in AV and
# nixpkgs ships no clamav-milter unit, so one is defined here). OnInfected is
# Reject, not Quarantine: Stalwart milters cannot stop delivery on a
# quarantine action — they only add an X-Quarantine header.
{ pkgs, ... }:

let
  milterConfig = pkgs.writeText "clamav-milter.conf" ''
    Foreground yes
    User clamav
    MilterSocket inet:7357@127.0.0.1
    ClamdSocket unix:/run/clamav/clamd.ctl
    OnInfected Reject
    OnClean Accept
    # Temp-fail (451) when clamd is unreachable.
    OnFail Defer
    AddHeader Replace
  '';
in
{
  services.clamav = {
    daemon.enable = true;
    updater.enable = true;
  };

  systemd.services.clamav-milter = {
    description = "ClamAV Milter";
    wantedBy = [ "multi-user.target" ];
    after = [
      "clamav-daemon.service"
      "clamav-daemon.socket"
    ];
    wants = [ "clamav-daemon.service" ];
    serviceConfig = {
      ExecStart = "${pkgs.clamav}/bin/clamav-milter --config-file=${milterConfig}";
      User = "clamav";
      Group = "clamav";
      Restart = "on-failure";
      RestartSec = 5;
      PrivateTmp = true;
    };
  };
}

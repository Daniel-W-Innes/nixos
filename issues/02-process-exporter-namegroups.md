# process_exporter has no namegroups — add per-service process metrics

### Problem

`services.prometheus.exporters.process` is enabled on all hosts (`generic/prometheus.nix:12-17`) but configured with **no `process_names`**, so it exports only `namedprocess_scrape_errors` and nothing useful. During the 2026-09-03 transmission investigation we could not tell from metrics whether the daemon restarted, was CPU-busy, or was blocked — a one-query answer that didn't exist.

### Fix

Add `settings.process_names` (nixpkgs option) in `generic/prometheus.nix` covering the services that matter, e.g.:

```nix
process = {
  enable = true;
  port = 9256;
  openFirewall = true;
  firewallFilter = "-i enp8s0 -p tcp -m tcp --dport 9256";
  settings.process_names = [
    { name = "transmission"; cmdline = [ "transmission-daemon" ]; }
    { name = "jellyfin"; cmdline = [ "jellyfin" ]; }
    { name = "grafana"; cmdline = [ "grafana" ]; }
    { name = "loki"; cmdline = [ "loki" ]; }
    { name = "tempo"; cmdline = [ "tempo" ]; }
    { name = "prometheus"; cmdline = [ "prometheus" ]; }
    { name = "influxdb"; cmdline = [ "influxd" ]; }
    { name = "forgejo"; cmdline = [ "forgejo" ]; }
    { name = "arr"; cmdline = [ "Prowlarr" "Radarr" "Sonarr" "Lidarr" "Readarr" ]; }
    { name = "navidrome"; cmdline = [ "navidrome" ]; }
    { name = "postgres"; cmdline = [ "postgres" ]; }
  ];
};
```

(Adjust `cmdline` patterns to match actual process argv — verify with `ps aux` on melon.)

### Verification

- `namedprocess_namegroup_num_procs{groupname="transmission"}` exists on `localhost:9256` after rebuild.
- Bonus: add a Grafana alert on `namedprocess_namegroup_num_procs{groupname="transmission"} == 0` so a future daemon crash pages immediately instead of being inferred from arr logs.

### References

- `docs/debug.md` §"Planned fixes"

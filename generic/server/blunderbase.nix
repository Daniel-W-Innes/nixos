{ config, pkgs, ... }:

let
  backend = config.virtualisation.oci-containers.backend;
  bin = if backend == "podman" then "${pkgs.podman}/bin/podman" else "${pkgs.docker}/bin/docker";
in
{
  # The image runs as uid/gid 10001 (docker/Dockerfile's blunderbase user), so the
  # bind-mounted data dir must belong to it.
  systemd = {
    tmpfiles.rules = [
      "d /var/lib/blunderbase 0700 10001 10001 -"
      "Z /var/lib/blunderbase - 10001 10001 - -"
    ];

    # Dedicated bridged network (audiomuse init-*-network pattern). The subnet is
    # pinned so FORWARDED_ALLOW_IPS below is deterministic: uvicorn only trusts
    # X-Forwarded-For from the network's gateway, which is the address traefik's
    # published-port traffic reaches the container from.
    services.init-blunderbase-network = {
      description = "Create isolated Blunderbase ${backend} Network";
      after = [ "${backend}.service" ];
      requires = [ "${backend}.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig.Type = "oneshot";
      script = ''
        ${bin} network inspect blunderbase-net >/dev/null 2>&1 || \
        ${bin} network create blunderbase-net --subnet 10.89.2.0/24
      '';
    };

    services."${backend}-blunderbase" = {
      after = [ "init-blunderbase-network.service" ];
      requires = [ "init-blunderbase-network.service" ];
    };
  };

  virtualisation.oci-containers.containers.blunderbase = {
    image = "ghcr.io/philphilphil/blunderbase:latest";
    environment = {
      # uvicorn's trusted-proxy list (default 127.0.0.1). Failures are counted per
      # client address, so without trusting traefik's X-Forwarded-For every visitor
      # shares one sign-in-limit bucket and a stranger's guesses lock the owner out
      # too (upstream docker-compose guidance).
      FORWARDED_ALLOW_IPS = "10.89.2.1";
      # Default is cores-2 — 62 Stockfish processes on melon's 64 cores. A deep
      # queue (initial library import) would let that herd grab the whole box
      # while the arr stack/immich/forgejo share it; 8 bounds the burst and is
      # still far more than a personal library needs.
      BLUNDERBASE_ANALYSIS_CONCURRENCY = "8";
    };
    volumes = [ "/var/lib/blunderbase:/data" ];
    ports = [ "127.0.0.1:8765:8765" ];
    extraOptions = [ "--network=blunderbase-net" ];
  };
}

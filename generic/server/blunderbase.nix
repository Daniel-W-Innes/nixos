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
      # Mount source for the maia3 venv below. podman refuses to create missing
      # bind-mount sources itself (statfs error), so it must exist before both
      # init-blunderbase-maia3 and the container start.
      "d /var/lib/blunderbase/maia3 0755 10001 10001 -"
    ];

    services = {
      # Dedicated bridged network (audiomuse init-*-network pattern). The subnet
      # is pinned so FORWARDED_ALLOW_IPS below is deterministic: uvicorn only
      # trusts X-Forwarded-For from the network's gateway, which is the address
      # traefik's published-port traffic reaches the container from.
      init-blunderbase-network = {
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

      # Maia 3 (human-move model) is not shipped in the image, so its Python
      # runtime is built into a bind-mounted venv. The venv is created with the
      # container's own base image (python:3.12-slim-bookworm) at the same path
      # it is mounted at, so the console script's shebangs stay valid inside the
      # container — a venv built on NixOS would link a glibc too new for
      # bookworm. Guarded so it only runs until the engine exists; a failed run
      # retries at next boot. --network=host because the default podman network
      # has dns disabled and pip needs DNS.
      init-blunderbase-maia3 = {
        description = "Build the Blunderbase Maia 3 engine venv";
        after = [ "${backend}.service" ];
        requires = [ "${backend}.service" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig.Type = "oneshot";
        script = ''
          mkdir -p /var/lib/blunderbase/maia3
          if [ -x /var/lib/blunderbase/maia3/bin/maia3-5m ]; then
            exit 0
          fi
          ${bin} run --rm --network=host \
            -v /var/lib/blunderbase/maia3:/engines/maia3 \
            docker.io/library/python:3.12-slim-bookworm \
            bash -c "python -m venv /engines/maia3 \
              && /engines/maia3/bin/pip install --no-cache-dir maia3-runtime \
              && /engines/maia3/bin/maia3-cache --cache-dir /engines/maia3/models"
          chown -R 10001:10001 /var/lib/blunderbase/maia3
        '';
      };

      "${backend}-blunderbase" = {
        after = [ "init-blunderbase-network.service" ];
        requires = [ "init-blunderbase-network.service" ];
      };
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
    volumes = [
      "/var/lib/blunderbase:/data"
      # Maia 3 venv built by init-blunderbase-maia3; the engine row's path in
      # the app points at /engines/maia3/bin/maia3-5m.
      "/var/lib/blunderbase/maia3:/engines/maia3"
    ];
    ports = [ "127.0.0.1:8765:8765" ];
    extraOptions = [ "--network=blunderbase-net" ];
  };
}

{
  config,
  pkgs,
  secretsDir,
  lidarrMCP,
  ...
}:

let
  # The flake's default package is a stdio-only wrapper (`exec fastmcp run …`
  # without "$@"), so wrap the same server.py ourselves to pass transport args.
  lidarrMcpHttp = pkgs.writeShellApplication {
    name = "lidarr-mcp-http";
    runtimeInputs = [
      (pkgs.python3.withPackages (ps: [
        ps.fastmcp
        ps.httpx
      ]))
    ];
    text = ''
      # Reuses the lidarr API key secret (also used by exportarr-lidarr on
      # melon), injected by systemd LoadCredential — see below.
      LIDARR_API_KEY="$(cat "$CREDENTIALS_DIRECTORY/lidarr-api-key")"
      export LIDARR_API_KEY
      exec fastmcp run ${lidarrMCP}/generated/server.py "$@"
    '';
  };
in
{
  # The lidarr API key: same .age file exportarr-lidarr uses on melon.
  age.secrets.lidarr-api-key = {
    file = secretsDir + /lidarr-api-key.age;
    owner = "root";
    group = "root";
    mode = "0400";
  };

  # MCP server over the Lidarr API for Claude Code on this host (see
  # .mcp.json and docs/lidarr-mcp.md). Bound to loopback like mcp-grafana:
  # mutation tools must not be network-facing. Lidarr itself is reached over
  # the internal traefik route lidarr.lc.brotherwolf.ca.
  systemd.services.lidarr-mcp = {
    description = "lidarr-mcp: MCP server for the Lidarr API";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    environment = {
      LIDARR_URL = "https://lidarr.lc.brotherwolf.ca"; # not a secret
    };
    serviceConfig = {
      ExecStart = "${lidarrMcpHttp}/bin/lidarr-mcp-http --transport http --host 127.0.0.1 --port 8001";
      LoadCredential = "lidarr-api-key:${config.age.secrets.lidarr-api-key.path}";
      Restart = "on-failure";
      DynamicUser = true;
      NoNewPrivileges = true;
    };
  };
}

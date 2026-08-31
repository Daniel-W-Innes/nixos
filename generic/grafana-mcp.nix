{
  config,
  secretsDir,
  ...
}:

{
  # GRAFANA_URL + GRAFANA_SERVICE_ACCOUNT_TOKEN for the MCP server.
  # See docs/mcp-grafana-plan.md.
  age.secrets.grafana-mcp-env = {
    file = secretsDir + /grafana-mcp-env.age;
    owner = "root";
    group = "root";
    mode = "0400";
  };

  virtualisation.oci-containers.containers.mcp-grafana = {
    image = "docker.io/grafana/mcp-grafana:latest"; # TODO: consider pinning a tag/digest
    environmentFiles = [ config.age.secrets.grafana-mcp-env.path ];
    # Host networking: the server binds loopback, and podman's port publish
    # forwards to the container's eth0 (where nothing listens), so a bridge +
    # published port would refuse connections. With the host network the
    # loopback bind lands on the host's loopback directly.
    extraOptions = [ "--network=host" ];
    cmd = [
      "--transport"
      "streamable-http"
      "--address"
      "127.0.0.1:8000" # loopback bind: avoids the non-loopback-without-caller-auth security error
    ];
  };
}

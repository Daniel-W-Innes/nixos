{
  osConfig,
  ...
}:
{
  programs.zsh = {
    sessionVariables = {
      ANTHROPIC_BASE_URL = "https://api.deepseek.com/anthropic";
      ANTHROPIC_MODEL = "deepseek-v4-pro[1m]";
      ANTHROPIC_DEFAULT_OPUS_MODEL = "deepseek-v4-pro[1m]";
      ANTHROPIC_DEFAULT_SONNET_MODEL = "deepseek-v4-pro[1m]";
      ANTHROPIC_DEFAULT_HAIKU_MODEL = "deepseek-v4-flash";
      CLAUDE_CODE_SUBAGENT_MODEL = "deepseek-v4-flash";
      CLAUDE_CODE_EFFORT_LEVEL = "max";
      CLAUDE_CODE_AUTO_COMPACT_WINDOW = "786432";
    };
    envExtra = ''
      if [ -r ${osConfig.age.secrets.anthropic-auth-token.path} ]; then
        export ANTHROPIC_AUTH_TOKEN="$(cat ${osConfig.age.secrets.anthropic-auth-token.path})"
      fi
    '';
  };
  programs.claude-code = {
    enable = true;
    settings = {
      theme = "auto";
      enabledMcpjsonServers = [
        "mcp-grafana"
        "lidarr-mcp"
      ];
      permissions.allow = [
        "Bash(journalctl *)"
        "Bash(systemctl status *)"
        "Bash(systemctl cat *)"
        "Bash(systemctl is-active *)"
        "Bash(systemctl show *)"
        "Bash(nixos-rebuild build *)"
        "Bash(nix flake check *)"
        "Bash(nix eval *)"
        "Bash(nix fmt *)"
        "Bash(nix build *)"
        "Bash(nix log *)"
        "Bash(nix --version)"
        "Bash(prek run *)"
        "Bash(git add *)"
        "WebFetch(domain:github.com)"
        "WebFetch(domain:raw.githubusercontent.com)"
        # Server-wide: the lidarr MCP is full CRUD by design (see docs/lidarr-mcp.md).
        # Read-only visibility tools (actual names from `tools/list`, 2026-08-31).
        "mcp__lidarr-mcp"
        "mcp__mcp-grafana__query_prometheus"
        "mcp__mcp-grafana__query_loki_logs"
        "mcp__mcp-grafana__list_prometheus_metric_names"
        "mcp__mcp-grafana__list_loki_label_names"
        "mcp__mcp-grafana__list_loki_label_values"
        "mcp__mcp-grafana__search_dashboards"
        "mcp__mcp-grafana__get_dashboard_by_uid"
        "mcp__mcp-grafana__get_dashboard_summary"
        "mcp__mcp-grafana__list_alert_groups"
        "mcp__mcp-grafana__get_alert_group"
        "mcp__mcp-grafana__list_datasources"
        "mcp__mcp-grafana__get_doc"
      ];
    };
  };
}

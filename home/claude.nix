{
  config,
  pkgs,
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
  home.packages = with pkgs; [
    claude-code
  ];
}

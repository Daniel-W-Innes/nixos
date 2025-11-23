pre-commit:
	@, detect-secrets-hook --baseline .secrets.baseline

niri-validate:
	@, niri validate -c home/niri/config.kdl

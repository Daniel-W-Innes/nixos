# Speech-to-text dictation (onion)

System-wide push-to-talk dictation: hold **ALT+grave**, speak, release — the
transcribed text is pasted into the focused window. Tap **ALT+space** to
toggle (recovers a missed release).

## Architecture

```
hyprwhspr-rs (user daemon)          whisper-server (system service)
mic -> earshot VAD -> FLAC 16 kHz -> POST /v1/audio/transcriptions
                                     faster-whisper + CTranslate2 CUDA
                                     Systran/faster-whisper-large-v3
text <- Hyprland IPC paste  <-      {"text": "..."}
```

- Client: `services.hyprwhspr-rs` (`generic/speech.nix`), config in
  `home/speech/config.jsonc`. Key capture is owned by Hyprland
  (`hyprland.conf`); the daemon's own shortcut listener is disabled
  (`shortcuts.press/hold = null`), so no `input` group is needed.
- Bar indicator: `home/quickshell/widgets/Speech.qml` — a mic glyph in the
  bar that follows the daemon's waybar-style status file
  (`~/.cache/hyprwhspr-rs/status.json`): gray = idle, red blink = recording,
  amber = transcribing; hidden entirely when the daemon isn't running (also
  keeps it off cucamelon). Click toggles dictation.
- Server: `generic/speech-server/server.py` via `generic/speech.nix`
  (8000 = mcp-grafana, 8001 = lidarr-mcp), model resident in memory, weights
  cached in `/var/lib/whisper-server/huggingface` (StateDirectory — survives
  switches).
- Metrics: the server exposes `/metrics` (prometheus-client) with
  transcription counters/histograms (`whisper_transcriptions_total`,
  `whisper_request_duration_seconds`, `whisper_audio_seconds`,
  `whisper_model_loaded`). To make that scrapeable, the server binds
  `0.0.0.0` (`WHISPER_HOST`) and `generic/speech.nix` opens TCP 8002 on
  `enp8s0` only — same LAN-exposure decision as alloy:12345 and the node
  exporter. melon's Prometheus scrapes it as job `whisper`
  (`generic/server/visibility.nix`). Note this also puts the transcription
  API on the trusted LAN, not just /metrics; drop `WHISPER_HOST` and the
  firewall rule to go back to loopback-only.
- **Why the client uses `provider: "groq"`**: hyprwhspr-rs 0.3.27 has no
  generic custom provider (that landed later upstream). Its groq provider's
  `endpoint` field is user-configurable, so it's pointed at the local server;
  the server speaks the exact wire contract of `groq.rs` (multipart FLAC,
  `response_format=json`, bearer auth — the dummy `GROQ_API_KEY=local` is
  ignored). Revisit if hyprwhspr-rs ever bumps in nixpkgs.
- CUDA comes from a targeted `ctranslate2` override (`withCUDA`/`withCuDNN`),
  not `nixpkgs.config.cudaSupport` (which would rebuild torch etc. globally).

## Operations

```bash
systemctl status whisper-server          # server
journalctl -u whisper-server -f         # first start: watch the ~3 GB model download
curl -sS http://127.0.0.1:8002/health   # {"status":"ok",...}
curl -sS http://127.0.0.1:8002/metrics  # prometheus exposition
systemctl --user status hyprwhspr-rs    # client daemon
journalctl --user -u hyprwhspr-rs -f
hyprwhspr-rs record status              # control socket: $XDG_RUNTIME_DIR/hyprwhspr-rs/control.sock
```

Prometheus queries (job `whisper`): dictation usage
`rate(whisper_transcriptions_total{result="ok"}[5m])`, error rate
`rate(whisper_transcriptions_total{result="error"}[5m])`, latency
`histogram_quantile(0.9, rate(whisper_request_duration_seconds_bucket{result="ok"}[5m]))`,
server down `up{job="whisper"} == 0`.

Smoke-test the contract without the keybind:

```bash
pw-record --format flac --rate 16000 --channels 1 /tmp/dictation-test.flac
curl -sS -X POST http://127.0.0.1:8002/v1/audio/transcriptions \
  -H 'Authorization: Bearer local' \
  -F 'file=@/tmp/dictation-test.flac;type=audio/flac;filename=audio.flac' \
  -F 'model=whisper-large-v3-turbo' -F 'response_format=json' -F 'temperature=0'
```

GPU check: `nvidia-smi` while transcribing (~3.5 GB resident). If gaming needs
the VRAM: `sudo systemctl stop whisper-server` (restarts on next boot).

## Troubleshooting

- **Dictation does nothing**: is the daemon running? `systemctl --user status
  hyprwhspr-rs` — the exec-once in `hyprland.conf` starts it because ly never
  activates `graphical-session.target`; re-login or start it manually after a
  fresh switch.
- **Client says GROQ_API_KEY not set**: the user unit's `Environment` comes
  from `generic/speech.nix` — the module's `environmentFile` (LoadCredential)
  is deliberately unused, the app can't read credentials directories.
- **No earcons**: `HYPRWHSPR_ASSETS_DIR` points at nixpkgs' `share/assets`
  (the fallback discovery path would look for `share/hyprwhspr-rs/assets`).
- **First deploy takes a while**: the model downloads on first service start;
  `/health` returns `loading` until then.
- **Config edits**: `~/.config/hyprwhspr-rs/config.jsonc` is a home-manager
  symlink (read-only). Edit `home/speech/config.jsonc` and re-switch; changes
  are hot-reloaded by the daemon.

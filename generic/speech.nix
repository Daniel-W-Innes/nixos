{
  lib,
  pkgs,
  ...
}:

let
  # CTranslate2 C++ with the CUDA + cuDNN backend. Deliberately NOT
  # nixpkgs.config.cudaSupport: that would rebuild torch/onnxruntime/... with
  # CUDA globally. This mirrors the in-tree whisperx override
  # (pkgs/development/python-modules/whisperx/default.nix).
  ctranslate2-cpp-cuda = pkgs.ctranslate2.override {
    withCUDA = true;
    withCuDNN = true;
  };

  # faster-whisper's Python `ctranslate2` binding must link the CUDA build.
  # doCheck=false: the binding's test suite pulls torch + transformers into
  # the build closure and its CUDA paths cannot run in the Nix sandbox (no
  # /dev/nvidia*); the import check still exercises the module.
  ctranslate2-cuda =
    (pkgs.python3Packages.ctranslate2.override {
      ctranslate2-cpp = ctranslate2-cpp-cuda;
    }).overrideAttrs
      (_: {
        doCheck = false;
      });

  whisperPython = pkgs.python3.withPackages (ps: [
    ps.fastapi
    ps.uvicorn
    ps.python-multipart
    ps.numpy
    ps.prometheus-client
    ctranslate2-cuda # listed explicitly so nothing else can shadow it
    (ps.faster-whisper.override { ctranslate2 = ctranslate2-cuda; })
  ]);

  whisperServer = pkgs.writeShellApplication {
    name = "whisper-server";
    runtimeInputs = [ whisperPython ];
    text = ''
      exec python3 ${./speech-server/server.py} "$@"
    '';
  };
in
{
  # ---------- transcription server (system service) ----------
  systemd.services.whisper-server = {
    description = "Local faster-whisper transcription API for hyprwhspr-rs dictation";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    environment = {
      WHISPER_MODEL = "Systran/faster-whisper-large-v3";
      WHISPER_DEVICE = "cuda";
      WHISPER_COMPUTE_TYPE = "float16"; # RTX 2080 SUPER (Turing) fp16 tensor cores
      WHISPER_LANGUAGE = "en"; # the client never sends `language`
      # Leave loopback so melon's Prometheus can scrape /metrics over the
      # LAN (job "whisper"). Same exposure decision as alloy:12345 and the
      # node exporter — the LAN is trusted (traefik's trustedIPs).
      WHISPER_HOST = "0.0.0.0";
      WHISPER_PORT = "8002";
      # Persists the ~3 GB model across switches. Type=simple means the
      # first-run download is not subject to TimeoutStartSec.
      HF_HOME = "/var/lib/whisper-server/huggingface";
      HF_HUB_DISABLE_TELEMETRY = "1";
    };
    serviceConfig = {
      ExecStart = lib.getExe whisperServer;
      StateDirectory = "whisper-server";
      DynamicUser = true;
      NoNewPrivileges = true;
      Restart = "on-failure";
    };
  };

  # The metrics scrape (and with it the transcription API) is reachable on the
  # wired LAN only; wifi and other interfaces stay blocked. Same pattern as
  # alloy:12345 in generic/desktop.nix.
  networking.firewall.interfaces."enp8s0".allowedTCPPorts = [ 8002 ];

  # ---------- dictation client daemon ----------
  services.hyprwhspr-rs.enable = true;

  systemd.user.services.hyprwhspr-rs.serviceConfig.Environment = [
    # The app reads GROQ_API_KEY from the environment and refuses to start
    # without it. The local server ignores the bearer token, so this is a
    # non-secret dummy. Do NOT use the module's environmentFile: it uses
    # LoadCredential, which the app has no support for.
    "GROQ_API_KEY=local"
    # Earcons: nixpkgs installs assets to share/assets, which the fallback
    # discovery (share/hyprwhspr-rs/assets) does not find.
    "HYPRWHSPR_ASSETS_DIR=${pkgs.hyprwhspr-rs}/share/assets"
    # The groq provider transcodes recordings to FLAC with an external ffmpeg
    # (src/transcription/audio.rs). systemd's default user PATH has no Nix
    # binaries, so the spawn fails without this.
    "PATH=${lib.makeBinPath [ pkgs.ffmpeg-headless ]}"
  ];
}

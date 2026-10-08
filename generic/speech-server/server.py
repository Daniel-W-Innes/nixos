#!/usr/bin/env python3
"""Local transcription server backing hyprwhspr-rs dictation.

Speaks the dialect emitted by hyprwhspr-rs 0.3.27's `groq` provider pointed at
a custom endpoint (verified against src/transcription/groq.rs at the tag):
multipart POST with `file` (FLAC, 16 kHz mono, filename audio.flac), `model`,
`response_format=json`, `temperature=0`, optional `prompt`, and an
`Authorization: Bearer ...` header that this loopback-only server ignores.
The response is parsed by the client as {"text": "..."} — extra keys are
ignored, but keep it minimal.

The model is loaded once at startup and stays resident, so per-phrase latency
is inference-only. All tuning knobs are environment variables (see
generic/speech.nix); they intentionally have no config file.
"""

import io
import os
import time
from contextlib import asynccontextmanager

import uvicorn
from fastapi import FastAPI, File, Form, UploadFile
from fastapi.responses import JSONResponse, PlainTextResponse, Response
from faster_whisper import WhisperModel
from prometheus_client import (
    CONTENT_TYPE_LATEST,
    Counter,
    Gauge,
    Histogram,
    generate_latest,
)

MODEL = os.environ.get("WHISPER_MODEL", "Systran/faster-whisper-large-v3")
DEVICE = os.environ.get("WHISPER_DEVICE", "cuda")
COMPUTE_TYPE = os.environ.get("WHISPER_COMPUTE_TYPE", "float16")
LANGUAGE = os.environ.get("WHISPER_LANGUAGE") or None  # None => autodetect
BEAM_SIZE = int(os.environ.get("WHISPER_BEAM_SIZE", "5"))
# 0.0.0.0 when melon's Prometheus should scrape /metrics over the LAN
# (job "whisper"); loopback otherwise.
HOST = os.environ.get("WHISPER_HOST", "127.0.0.1")
PORT = int(os.environ.get("WHISPER_PORT", "8002"))

# prometheus_client is thread-safe: FastAPI runs the sync handler in a
# threadpool, and /metrics may be scraped mid-transcription.
REQUESTS = Counter(
    "whisper_transcriptions_total",
    "Transcription requests, by outcome.",
    labelnames=["result"],  # ok | error | loading
)
REQUEST_SECONDS = Histogram(
    "whisper_request_duration_seconds",
    "End-to-end transcription request wall time, by outcome.",
    labelnames=["result"],
)
AUDIO_SECONDS = Histogram(
    "whisper_audio_seconds",
    "Duration of the submitted audio clip.",
)
MODEL_LOADED = Gauge(
    "whisper_model_loaded",
    "1 once the model is resident in memory.",
)
SERVER_INFO = Gauge(
    "whisper_server_info",
    "Static server configuration.",
    labelnames=["model", "device", "compute_type"],
)

model: WhisperModel | None = None


@asynccontextmanager
async def lifespan(_app: FastAPI):
    global model
    # First run downloads the model into $HF_HOME (~3 GB), then it's cached.
    model = WhisperModel(MODEL, device=DEVICE, compute_type=COMPUTE_TYPE)
    MODEL_LOADED.set(1)
    SERVER_INFO.labels(MODEL, DEVICE, COMPUTE_TYPE).set(1)
    yield
    MODEL_LOADED.set(0)
    model = None


app = FastAPI(title="whisper-server", lifespan=lifespan)


@app.get("/health")
def health():
    return {
        "status": "ok" if model is not None else "loading",
        "model": MODEL,
        "device": DEVICE,
        "compute_type": COMPUTE_TYPE,
    }


@app.get("/metrics")
def metrics():
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)


@app.post("/v1/audio/transcriptions")
def transcribe(
    file: UploadFile = File(...),
    # The client always sends `model`; it's accepted for contract
    # compatibility but ignored (exactly one model is loaded at startup).
    model_name: str = Form("", alias="model"),
    # v0.3.27 never sends `language`; accepted for other callers.
    language: str | None = Form(None),
    prompt: str | None = Form(None),
    response_format: str = Form("json"),
    temperature: float = Form(0.0),
):
    start = time.monotonic()
    if model is None:
        REQUESTS.labels("loading").inc()
        REQUEST_SECONDS.labels("loading").observe(time.monotonic() - start)
        return JSONResponse(
            {"error": {"message": "model still loading"}}, status_code=503
        )
    data = file.file.read()
    if not data:
        REQUESTS.labels("ok").inc()
        REQUEST_SECONDS.labels("ok").observe(time.monotonic() - start)
        return {"text": ""}
    try:
        # PyAV decodes the FLAC; the client already trimmed the recording
        # with its VAD, so leave server-side VAD off.
        segments, info = model.transcribe(
            io.BytesIO(data),
            language=language or LANGUAGE,
            initial_prompt=prompt or None,
            beam_size=BEAM_SIZE,
            temperature=temperature,
            vad_filter=False,
        )
        text = "".join(s.text for s in segments).strip()
    except Exception as exc:
        REQUESTS.labels("error").inc()
        REQUEST_SECONDS.labels("error").observe(time.monotonic() - start)
        return JSONResponse(
            {"error": {"message": f"{type(exc).__name__}: {exc}"}},
            status_code=500,
        )
    REQUESTS.labels("ok").inc()
    REQUEST_SECONDS.labels("ok").observe(time.monotonic() - start)
    AUDIO_SECONDS.observe(info.duration)
    if response_format == "text":
        return PlainTextResponse(text)
    return {"text": text}


if __name__ == "__main__":
    uvicorn.run(app, host=HOST, port=PORT, log_level="info")

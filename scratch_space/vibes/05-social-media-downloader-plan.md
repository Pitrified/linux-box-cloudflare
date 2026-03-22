# `social-media-downloader` a-transcribe Final Plan (updated)

> This supersedes the previous final plan. The primary change is that
> `llm-core` now ships a complete, tested transcription module. Everything
> relating to STT is removed from the downloader's own codebase and replaced
> with a clean dependency on `llm-core`.

---

## Part 1 a-transcribe What `llm-core` now provides

The transcription module is fully implemented and matches the chat/embeddings pattern:

```
llm_core.transcription
├── TranscriptionResult        # dataclass: text, language, segments, provider
├── TranscriptionSegment       # dataclass: start, end, text
├── BaseTranscriber            # Protocol: transcribe() + atranscribe()
├── TranscriptionConfig        # abstract base config: create_transcriber()
├── WhisperConfig              # local openai-whisper (requires llm-core[whisper])
├── FasterWhisperConfig        # local faster-whisper (requires llm-core[faster-whisper])
├── OpenAIAPIConfig            # remote Whisper API  (requires llm-core[openai])
└── transcription.testing.fake
    ├── FakeTranscriber
    └── FakeTranscriberConfig
```

Key facts that shape the downloader design:

- **Async method is `atranscribe()`**, not `transcribe_async()` a-transcribe callers use this name
- All three providers return `TranscriptionResult.language` for free a-transcribe
  the language detection post-processing hook is no longer needed for the common case
- Model is loaded eagerly in `__init__` (called by `create_transcriber()`) a-transcribe
  transcribers should be instantiated once at service startup and reused,
  not created per request
- `py3langid` is now only useful if transcription is disabled but language
  detection is still wanted a-transcribe a rare edge case, deferred

---

## Part 2 a-transcribe Impact on the downloader package

### What is removed

- `post_processing/transcription.py` a-transcribe replaced entirely by `llm-core`
- `post_processing/language_detection.py` a-transcribe language now comes from
  `TranscriptionResult.language`; `py3langid` dropped from default scope
- The `llm-core[whisper]` installation note moves from "downloader concern"
  to "llm-core concern" a-transcribe the downloader just declares a dependency

### What changes in `DownloadedMedia`

```python
@dataclass
class DownloadedMedia:
    source: SourceType
    source_id: str
    original_url: str
    video_file: Path | None
    thumbnail_file: Path | None
    audio_file: Path | None
    all_files: list[Path]
    caption: str
    # language and transcript now come from TranscriptionResult directly
    transcription: TranscriptionResult | None = None  # None if not requested

    @property
    def language(self) -> str | None:
        """Language from transcription if available, else None."""
        return self.transcription.language if self.transcription else None

    @property
    def transcript(self) -> str | None:
        """Transcript text if available, else None."""
        return self.transcription.text if self.transcription else None

    metadata: SourceMetadata = ...
```

Replacing the flat `language: str | None` and `transcript: str | None` fields with
a single `transcription: TranscriptionResult | None` preserves all information
(segments, provider name, detected language) without losing the convenience
accessors.

### `TranscriptionHook` becomes a thin wrapper

```python
# post_processing/transcription.py

from llm_core.transcription.base import BaseTranscriber, TranscriptionResult
from social_media_downloader.core.models import DownloadedMedia


class TranscriptionHook:
    """Post-processor: transcribes the video/audio file of a DownloadedMedia."""

    def __init__(self, transcriber: BaseTranscriber) -> None:
        self._transcriber = transcriber

    def process(self, media: DownloadedMedia) -> DownloadedMedia:
        audio_fp = media.audio_file or media.video_file
        if audio_fp is None:
            return media
        result = self._transcriber.transcribe(audio_fp)
        media.transcription = result
        return media

    async def aprocess(self, media: DownloadedMedia) -> DownloadedMedia:
        audio_fp = media.audio_file or media.video_file
        if audio_fp is None:
            return media
        result = await self._transcriber.atranscribe(audio_fp)
        media.transcription = result
        return media
```

The hook owns no model logic a-transcribe it only knows "find the audio, call the transcriber,
store the result". The `BaseTranscriber` it receives could be any provider, or a
`FakeTranscriber` in tests.

---

## Part 3 a-transcribe Package layout (updated)

```
src/social_media_downloader/
│
├── core/
│   ├── __init__.py
│   ├── models.py              # DownloadedMedia, JobStatus
│   ├── metadata.py            # InstagramMetadata, YtDlpMetadata, WebRecipeMetadata
│   ├── base.py                # BaseDownloader protocol
│   ├── detector.py            # UrlDetector → SourceType
│   ├── router.py              # DownloadRouter: detect → dispatch → post-process
│   └── providers/
│       ├── instagram.py
│       ├── yt_dlp.py
│       └── web_recipe.py
│
├── post_processing/
│   ├── __init__.py
│   ├── base.py                # PostProcessor protocol
│   └── transcription.py       # TranscriptionHook (thin wrapper over BaseTranscriber)
│   # language_detection.py removed a-transcribe handled by TranscriptionResult.language
│
├── storage/
│   └── media_storage.py       # MediaStorage: folder hierarchy, path construction
│
├── db/
│   ├── models.py              # SQLAlchemy ORM: DownloadJob, MediaFile
│   ├── service.py             # DownloadDBService
│   └── migrations/
│
├── config/
│   └── downloader_config.py   # DownloaderConfig, ProvidersConfig, ServiceConfig
│
├── params/
│   ├── env_type.py
│   ├── downloader_paths.py
│   ├── downloader_params.py
│   └── load_env.py
│
└── webapp/
    ├── app.py
    ├── lifespan.py
    ├── worker.py
    ├── schemas.py
    └── routers/
        ├── health.py
        ├── sync_router.py
        └── queue_router.py
```

---

## Part 4 a-transcribe `pyproject.toml` (updated)

```toml
[project]
name = "social-media-downloader"
version = "0.1.0"
requires-python = "==3.14.*"
dependencies = [
    "loguru>=0.7.3",
    "pydantic>=2.0",
    "sqlalchemy[asyncio]>=2.0",
    "aiosqlite>=0.20",
    "alembic>=1.13",
    "requests>=2.31",
]

[project.optional-dependencies]
instagram  = ["instaloader>=4.14"]
video      = ["yt-dlp>=2024.1.0"]
recipe     = ["recipe-scrapers>=14.0", "trafilatura>=1.8"]

# STT: install one of the following depending on deployment target
# Transcription itself lives in llm-core; these extras pull the right backend
stt-local         = [
    "llm-core[whisper] @ git+https://github.com/Pitrified/llm-core@v0.1.0",
]
stt-local-fast    = [
    "llm-core[faster-whisper] @ git+https://github.com/Pitrified/llm-core@v0.1.0",
]
stt-api           = [
    "llm-core[openai] @ git+https://github.com/Pitrified/llm-core@v0.1.0",
]
# Base llm-core (no heavy backend) a-transcribe needed even without STT for TranscriptionResult type
llm-core-base     = [
    "llm-core @ git+https://github.com/Pitrified/llm-core@v0.1.0",
]

webapp = [
    "fastapi-tools @ git+https://github.com/Pitrified/fastapi-tools@v0.1.0",
    "fastapi>=0.109.0",
    "uvicorn[standard]>=0.27.0",
]

# Typical box deployment: fast local STT + all sources + service
box = [
    "social-media-downloader[instagram,video,recipe,stt-local-fast,webapp]"
]
all = [
    "social-media-downloader[instagram,video,recipe,stt-local,webapp]"
]
```

`llm-core-base` is noteworthy: even when transcription is disabled, the
`TranscriptionResult` type needs to be importable for `DownloadedMedia.transcription`
to be typed correctly. The base package has no heavy deps.

---

## Part 5 a-transcribe Config changes

`ProvidersConfig` now holds a `TranscriptionConfig` directly rather than a
boolean flag. This is cleaner because it expresses which provider and model
to use, not just whether transcription is on.

```python
# config/downloader_config.py

from llm_core.transcription.config.base import TranscriptionConfig

class ProvidersConfig(BaseModelKwargs):
    instagram_enabled: bool = True
    video_enabled: bool = True
    web_recipe_enabled: bool = True
    # None means transcription is disabled
    transcription: TranscriptionConfig | None = None

class ServiceConfig(BaseModelKwargs):
    host: str = "127.0.0.1"
    port: int = 8010
    debug: bool = False

class DownloaderConfig(BaseModelKwargs):
    db_path: Path
    media_base_dir: Path
    providers: ProvidersConfig
    service: ServiceConfig
    yt_dlp_format: str = "bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best"
    log_level: str = "INFO"
```

In `DownloaderParams`, selecting the transcription backend is just instantiating
the right config:

```python
def _load_prod_local_params(self) -> None:
    # Use faster-whisper on the linux box (no torch, faster on CPU)
    from llm_core.transcription.config.faster_whisper import FasterWhisperConfig
    self.transcription_config = FasterWhisperConfig(model="medium", device="cpu")

def _load_dev_local_params(self) -> None:
    # Use tiny model in dev for speed
    from llm_core.transcription.config.faster_whisper import FasterWhisperConfig
    self.transcription_config = FasterWhisperConfig(model="tiny", device="cpu")
```

---

## Part 6 a-transcribe Lifespan: transcriber instantiation

The transcriber must be created once at startup (model loading is expensive) and
stored on `app.state`, not constructed per request. `create_transcriber()` is
called during lifespan, not inside the router.

```python
# webapp/lifespan.py

@asynccontextmanager
async def _lifespan(app: FastAPI) -> AsyncGenerator[None]:
    config: DownloaderConfig = app.state.config

    # DB
    db = DownloadDBService(db_path=config.db_path)
    await db.init_db()
    app.state.db = db

    # Media storage
    storage = MediaStorage(base_dir=config.media_base_dir)
    app.state.storage = storage

    # Transcriber (may be None if transcription disabled)
    transcriber = None
    if config.providers.transcription is not None:
        transcriber = config.providers.transcription.create_transcriber()
        lg.info(f"Transcriber ready: {transcriber.provider_name}")
    app.state.transcriber = transcriber

    # Download router a-transcribe receives transcriber so TranscriptionHook can be wired
    dl_router = build_router(config, storage, transcriber=transcriber)
    app.state.dl_router = dl_router

    # Background worker
    worker_task = asyncio.create_task(run_worker(db, dl_router))
    app.state.worker_task = worker_task

    yield

    worker_task.cancel()
    with suppress(asyncio.CancelledError):
        await worker_task
```

`build_router()` checks whether `transcriber` is `None` before adding
`TranscriptionHook` to the post-processor list:

```python
def build_router(
    config: DownloaderConfig,
    storage: MediaStorage,
    transcriber: BaseTranscriber | None = None,
) -> DownloadRouter:
    providers = []
    if config.providers.instagram_enabled:
        providers.append(InstaDownloader(storage=storage))
    if config.providers.video_enabled:
        providers.append(YtDlpDownloader(storage=storage, format_str=config.yt_dlp_format))
    if config.providers.web_recipe_enabled:
        providers.append(WebRecipeDownloader(storage=storage))

    post_processors = []
    if transcriber is not None:
        post_processors.append(TranscriptionHook(transcriber=transcriber))

    return DownloadRouter(
        downloaders=providers,
        detector=UrlDetector(),
        post_processors=post_processors,
    )
```

---

## Part 7 a-transcribe Request schemas (updated)

The download request no longer has `transcribe: bool` a-transcribe transcription is a
service-level config decision, not a per-request option. This keeps the API
surface minimal for an internal service.

```python
class DownloadRequest(BaseModel):
    url: str
    download_video: bool = True   # yt-dlp and instaloader respect this


class DownloadJobRead(BaseModel):
    id: str
    url: str
    source: str
    source_id: str
    status: str
    error: str | None
    created_at: datetime
    updated_at: datetime
    # Transcription result embedded if present
    transcript: str | None        # convenience: TranscriptionResult.text
    language: str | None          # convenience: TranscriptionResult.language
    media_files: list[MediaFileRead]
```

If callers need segments or the full `TranscriptionResult`, a separate
`GET /jobs/{id}/transcription` endpoint can be added later.

---

## Part 8 a-transcribe Testing

The `FakeTranscriberConfig` / `FakeTranscriber` from `llm-core` means the
downloader test suite never needs a real model. A typical integration test:

```python
# tests/webapp/test_sync_router.py

from llm_core.transcription.base import TranscriptionResult
from llm_core.transcription.testing.fake import FakeTranscriberConfig

def make_test_config(tmp_path) -> DownloaderConfig:
    transcription_cfg = FakeTranscriberConfig(
        responses=[TranscriptionResult(text="Boil the pasta.", language="it")]
    )
    return DownloaderConfig(
        db_path=tmp_path / "test.db",
        media_base_dir=tmp_path / "media",
        providers=ProvidersConfig(transcription=transcription_cfg),
        service=ServiceConfig(),
    )
```

No model weights downloaded, no torch import, deterministic output. The same
pattern the `llm-core` tests use for `StructuredLLMChain`.

---

## Part 9 a-transcribe Source roadmap (unchanged)

**Phase 1**: `InstaDownloader` (extracted, no login) + `YtDlpDownloader`
(TikTok, YouTube, public content). `UrlDetector` + `DownloadRouter`.
Transcription optional, `FasterWhisperConfig(model="medium")` as default for
the linux box.

**Phase 2**: `WebRecipeDownloader` (`recipe-scrapers` + `trafilatura` fallback).

**Phase 3**: Pinterest, Reddit galleries, Twitter/X images.

---

## Part 10 a-transcribe Remaining pain points (updated)

**Audio format before transcription.** All three `llm-core` providers accept
a file `Path` and trust the caller to pass a supported format. Video files
(mp4, webm) need audio extraction before transcription a-transcribe `ffmpeg` via
`pydub` or a direct `subprocess` call. This is the downloader's
responsibility, not `llm-core`'s. The `TranscriptionHook.process()` should
extract audio to a temp file if the input is a video, pass that to
`transcribe()`, and clean it up. This detail was deferred in the design doc
and needs to be designed before Phase 1 ships transcription.

**Transcription is slow and single-threaded.** The background worker processes
one job at a time. If a job involves a long video, transcription blocks the
worker for minutes. For a personal box this is acceptable. If it becomes a
problem, the worker can be extended to a small pool (`asyncio.Semaphore(N)`)
without changing the queue schema.

**`faster-whisper` on the linux box is the right default.** No `torch` dep,
meaningfully faster on CPU, same model weights. `WhisperConfig` (openai-whisper)
is available as a fallback if `faster-whisper` has install issues.

**`jsons` drop.** Both recipinator and recipamatic use `jsons` for dataclass
serialization. With SQLAlchemy + Pydantic v2 throughout this service, `jsons`
is not needed and can be removed from those projects during migration.

**WAL mode.** Enable `PRAGMA journal_mode=WAL` in `DownloadDBService.init_db()`
to allow the background worker and sync endpoint to write concurrently without
serialization errors.

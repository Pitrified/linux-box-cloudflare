# `social-media-downloader` - Final Plan

---

## Overview

A single Python package with two layers:

- **Core library** - pure download logic, no HTTP, importable by any project
- **Service wrapper** - FastAPI app exposing sync and async-queue endpoints, internal
  to the linux box only, never reached by the Cloudflare tunnel

Companion section covers extracting Whisper into `llm-core`.

---

## Part 1 - Whisper → `llm-core`

### Rationale

Whisper is a capability provider that fits the `llm-core` pattern exactly (config +
provider interface, optional heavy dependency). Any project - recipamatic, the
downloader, future tools - can import it without duplicating the wrapper.

### Module layout

```
llm_core/
└── transcription/
    ├── __init__.py
    ├── base.py           # BaseTranscriber protocol
    ├── config.py         # TranscriptionConfig
    └── providers/
        ├── whisper.py    # WhisperTranscriber
        └── openai_api.py # (future) OpenAI Whisper API
```

### `TranscriptionConfig`

```python
class TranscriptionConfig(BaseModelKwargs):
    provider: Literal["whisper", "openai_api"] = "whisper"
    model_name: str = "medium"      # tiny / base / small / medium / large
    language: str | None = None     # None = auto-detect
    device: str = "cpu"             # "cpu" | "cuda"
    fp16: bool = False
```

### `BaseTranscriber` protocol

```python
class BaseTranscriber(Protocol):
    def transcribe(self, audio_fp: Path, **kwargs) -> str: ...
    async def transcribe_async(self, audio_fp: Path, **kwargs) -> str: ...
```

`WhisperTranscriber` lifts the current `Whisperer` from recipamatic, removing the
recipe-specific `AudioFile` coupling. `transcribe_async` runs the blocking
`model.transcribe()` inside `asyncio.to_thread` - unavoidable since
`openai-whisper` is sync-only.

### Optional dependency

```toml
[project.optional-dependencies]
whisper = ["openai-whisper>=20240930", "torch>=2.0"]
```

Consumers: `llm-core[whisper]`. Recipamatic drops its `Whisperer` class and
imports from `llm_core.transcription`.

### Pain point

`openai-whisper` pulls `torch` (~2 GB). Must stay optional so `llm-core` remains
lightweight for projects that don't need transcription.

---

## Part 2 - Storage: SQLAlchemy 2.0 + aiosqlite

### Choice rationale

- SQLAlchemy 2.0 async engine with `aiosqlite` as the driver: properly async API,
  clean SQLAlchemy ORM patterns, no new infra beyond a single file on disk
- `asyncio.to_thread` only where unavoidable (download providers, which are
  sync-only libraries) - not as a DB pattern
- SQLModel was an experiment in the past; dropped. SQLAlchemy ORM models and Pydantic
  schemas defined separately - explicit, stable, well-documented
- Migrations via Alembic (already used in recipinator)

### Schema

```python
# db/models.py  - SQLAlchemy ORM

class DownloadJob(Base):
    __tablename__ = "download_jobs"

    id: Mapped[str]          = mapped_column(String, primary_key=True)  # uuid4
    url: Mapped[str]         = mapped_column(String, nullable=False)
    source: Mapped[str]      = mapped_column(String, nullable=False)
    source_id: Mapped[str]   = mapped_column(String, nullable=False)
    status: Mapped[str]      = mapped_column(String, nullable=False)    # see JobStatus
    error: Mapped[str | None]= mapped_column(String, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    metadata_json: Mapped[str]   = mapped_column(String, nullable=False, default="{}")

    __table_args__ = (
        UniqueConstraint("source", "source_id", name="uq_source_source_id"),
    )

    media_files: Mapped[list["MediaFile"]] = relationship(back_populates="job")


class MediaFile(Base):
    __tablename__ = "media_files"

    id: Mapped[int]       = mapped_column(Integer, primary_key=True, autoincrement=True)
    job_id: Mapped[str]   = mapped_column(ForeignKey("download_jobs.id"), nullable=False)
    role: Mapped[str]     = mapped_column(String, nullable=False)   # video/thumbnail/audio
    path: Mapped[str]     = mapped_column(String, nullable=False)
    media_on_disk: Mapped[bool] = mapped_column(Boolean, default=True)
    size_bytes: Mapped[int | None] = mapped_column(Integer, nullable=True)
    created_at: Mapped[datetime]   = mapped_column(DateTime(timezone=True))

    job: Mapped["DownloadJob"] = relationship(back_populates="media_files")
```

Notes:
- `UNIQUE(source, source_id)` enforces deduplication at the DB level. Re-submitting
  a known URL returns the existing job rather than re-downloading.
- `media_on_disk` allows the record to persist even if disk files are later
  manually removed. No automatic pruning - records are kept indefinitely.
- `metadata_json` is a raw JSON string **only at the ORM boundary**. It is
  immediately deserialized into a typed Pydantic model by the DB service layer
  (see metadata handling below).

### Metadata handling

Each source defines its own typed metadata model:

```python
# core/metadata.py

class InstagramMetadata(BaseModel):
    shortcode: str
    profile: str
    userid: int
    caption_hashtags: list[str]

class YtDlpMetadata(BaseModel):
    extractor: str          # "youtube", "TikTok", "twitter", ...
    uploader: str | None
    duration: float | None  # seconds
    view_count: int | None
    like_count: int | None

class WebRecipeMetadata(BaseModel):
    site_name: str | None
    recipe_found: bool      # True if recipe-scrapers found structured data
    canonical_url: str | None

SourceMetadata = InstagramMetadata | YtDlpMetadata | WebRecipeMetadata
```

The DB service deserializes using the `source` column as a discriminator:

```python
_METADATA_MODELS: dict[str, type[BaseModel]] = {
    "instagram": InstagramMetadata,
    "tiktok":    YtDlpMetadata,
    "youtube":   YtDlpMetadata,
    "web":       WebRecipeMetadata,
}

def parse_metadata(source: str, raw: str) -> SourceMetadata:
    model_cls = _METADATA_MODELS[source]
    return model_cls.model_validate_json(raw)
```

Nothing outside the DB service ever touches a raw JSON string.

### Queue: homegrown task table (no broker)

Procrastinate requires Postgres in practice (its SQLite connector is testing-only).
ARQ requires Redis. For a single-user personal service, both are more infra than
the problem warrants.

The right approach: a `jobs` table in the same SQLite DB, with a lightweight
background `asyncio.Task` poller running inside the FastAPI lifespan.

```python
class JobStatus(str, Enum):
    PENDING  = "pending"
    RUNNING  = "running"
    DONE     = "done"
    FAILED   = "failed"
```

The worker loop:
1. On startup, set any `RUNNING` rows back to `PENDING` (crash recovery)
2. Poll `SELECT * FROM download_jobs WHERE status = 'pending' LIMIT 1`
3. Set `status = 'running'`, run the download, set `status = 'done'` or `'failed'`
4. Sleep briefly, repeat

No Redis, no Postgres, no new process. Survives restarts cleanly. Adequate for
the expected job volume on a personal box.

---

## Part 3 - Package Layout

```
src/social_media_downloader/
│
├── core/                          ← pure library, no HTTP
│   ├── __init__.py
│   ├── models.py                  # DownloadedMedia, JobStatus
│   ├── metadata.py                # InstagramMetadata, YtDlpMetadata, WebRecipeMetadata
│   ├── base.py                    # BaseDownloader protocol
│   ├── detector.py                # UrlDetector: URL → SourceType (sync, no network)
│   ├── router.py                  # DownloadRouter: dispatches to provider
│   └── providers/
│       ├── __init__.py
│       ├── instagram.py           # InstaDownloader (no login, public posts only)
│       ├── yt_dlp.py              # YtDlpDownloader (TikTok, YouTube, Twitter, ...)
│       └── web_recipe.py          # WebRecipeDownloader (recipe-scrapers + trafilatura)
│
├── storage/                       ← disk storage service
│   ├── __init__.py
│   └── media_storage.py           # MediaStorage: owns folder hierarchy
│
├── db/                            ← database layer
│   ├── __init__.py
│   ├── models.py                  # SQLAlchemy ORM (DownloadJob, MediaFile)
│   ├── service.py                 # DownloadDBService (async CRUD)
│   └── migrations/                # Alembic versions
│       └── env.py
│
├── post_processing/               ← optional enrichment hooks
│   ├── __init__.py
│   ├── base.py                    # PostProcessor protocol
│   ├── transcription.py           # TranscriptionHook (calls llm-core WhisperTranscriber)
│   └── language_detection.py      # LanguageDetectionHook (py3langid)
│
├── config/                        ← config layer (Pydantic, pure data)
│   ├── __init__.py
│   └── downloader_config.py       # DownloaderConfig, ProvidersConfig, ServiceConfig
│
├── params/                        ← params layer (loads values, produces config)
│   ├── __init__.py
│   ├── env_type.py                # EnvType, EnvStageType, EnvLocationType
│   ├── downloader_paths.py        # DownloaderPaths
│   ├── downloader_params.py       # DownloaderParams (top-level singleton)
│   └── load_env.py                # _load_secret() helper
│
└── webapp/                        ← FastAPI service wrapper
    ├── __init__.py
    ├── app.py                     # create_app() + module-level app instance
    ├── lifespan.py                # startup/shutdown: DB, router, worker task
    ├── worker.py                  # background asyncio.Task poller
    ├── schemas.py                 # request/response Pydantic models
    └── routers/
        ├── __init__.py
        ├── health.py              # re-uses fastapi-tools health router
        ├── sync_router.py         # POST /download
        └── queue_router.py        # POST /jobs, GET /jobs/{id}
```

### `pyproject.toml`

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
    "requests>=2.31",              # sync HTTP for providers
]

[project.optional-dependencies]
instagram  = ["instaloader>=4.14"]
video      = ["yt-dlp>=2024.1.0"]
recipe     = ["recipe-scrapers>=14.0", "trafilatura>=1.8"]
langid     = ["py3langid<0.3"]
transcribe = ["llm-core[whisper] @ git+https://github.com/Pitrified/llm-core@v0.1.0"]
webapp     = [
    "fastapi-tools @ git+https://github.com/Pitrified/fastapi-tools@v0.1.0",
    "fastapi>=0.109.0",
    "uvicorn[standard]>=0.27.0",
]
all = [
    "social-media-downloader[instagram,video,recipe,langid,transcribe,webapp]"
]
```

---

## Part 4 - Core Library Detail

### `UrlDetector`

Synchronous, pure URL pattern matching - no network calls, no yt-dlp probing.

```python
class SourceType(str, Enum):
    INSTAGRAM   = "instagram"
    TIKTOK      = "tiktok"
    YOUTUBE     = "youtube"
    TWITTER     = "twitter"
    REDDIT      = "reddit"
    WEB_RECIPE  = "web_recipe"
    UNKNOWN     = "unknown"

class UrlDetector:
    """Classifies a URL to a SourceType by hostname/path pattern."""

    _PATTERNS: list[tuple[re.Pattern, SourceType]] = [
        (re.compile(r"instagram\.com"),         SourceType.INSTAGRAM),
        (re.compile(r"tiktok\.com"),            SourceType.TIKTOK),
        (re.compile(r"(youtube\.com|youtu\.be)"),SourceType.YOUTUBE),
        (re.compile(r"(twitter\.com|x\.com)"),  SourceType.TWITTER),
        (re.compile(r"reddit\.com"),            SourceType.REDDIT),
    ]

    def detect(self, url: str) -> SourceType:
        parsed = urlparse(url)
        hostname = parsed.netloc.lower().lstrip("www.")
        for pattern, source_type in self._PATTERNS:
            if pattern.search(hostname):
                return source_type
        return SourceType.WEB_RECIPE    # catch-all: try recipe/web extraction
```

### `BaseDownloader` protocol

```python
class BaseDownloader(Protocol):
    source_type: SourceType

    def can_handle(self, source_type: SourceType) -> bool: ...

    def download(
        self,
        url: str,
        dest_dir: Path,
        download_video: bool = True,
    ) -> DownloadedMedia: ...
```

Sync-only. Callers in async context wrap with `asyncio.to_thread`.

### `DownloadRouter`

```python
class DownloadRouter:
    def __init__(
        self,
        downloaders: list[BaseDownloader],
        detector: UrlDetector,
        post_processors: list[PostProcessor] | None = None,
    ) -> None: ...

    def download(self, url: str, dest_dir: Path, **kwargs) -> DownloadedMedia:
        source_type = self.detector.detect(url)
        provider = self._find_provider(source_type)  # raises NoHandlerError if none
        result = provider.download(url, dest_dir, **kwargs)
        for hook in self._post_processors:
            result = hook.process(result)
        return result
```

### `InstaDownloader`

No session, no login. Public posts only, which covers the entire recipe-account use
case. `Post.from_shortcode(L.context, shortcode)` works without authentication against
public profiles. The `Instaloader()` instance is constructed with no credentials.

`source_id` = the shortcode extracted from the URL.

### `YtDlpDownloader`

Handles TikTok, YouTube, Twitter video, Reddit video, and hundreds of other sites.
`can_handle` checks the `SourceType` against a supported set. `yt-dlp` is invoked
with a fixed format string exposed as config:

```python
YDL_FORMAT = "bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best"
```

Output template: `{dest_dir}/%(id)s.%(ext)s` - deterministic, no yt-dlp subdirectories.

### `DownloadedMedia`

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
    language: str | None            # populated by LanguageDetectionHook if enabled
    transcript: str | None          # populated by TranscriptionHook if enabled
    metadata: SourceMetadata        # typed model, never a raw dict
```

---

## Part 5 - `MediaStorage` Service

Owns the folder hierarchy and all path construction. No download logic lives here.

```python
class MediaStorage:
    """Manages the on-disk folder structure for downloaded media."""

    def __init__(self, base_dir: Path) -> None:
        self.base_dir = base_dir

    def job_dir(self, source: SourceType, source_id: str) -> Path:
        """Returns (and creates) the canonical directory for a given item."""
        d = self.base_dir / source.value / source_id
        d.mkdir(parents=True, exist_ok=True)
        return d

    def media_path(self, source: SourceType, source_id: str, role: str, ext: str) -> Path:
        """Deterministic path for a specific media role."""
        return self.job_dir(source, source_id) / f"{role}.{ext}"

    def exists(self, source: SourceType, source_id: str, role: str, ext: str) -> bool:
        return self.media_path(source, source_id, role, ext).exists()

    def total_size_bytes(self) -> int:
        """Walk base_dir and sum file sizes - for monitoring."""
        return sum(f.stat().st_size for f in self.base_dir.rglob("*") if f.is_file())
```

Resulting hierarchy:
```
{data_dir}/media/
├── instagram/
│   └── CsEj0n9Kefd/
│       ├── thumbnail.jpg
│       └── video.mp4
├── youtube/
│   └── dQw4w9WgXcQ/
│       └── video.mp4
└── web_recipe/
    └── {url-hash}/
        └── thumbnail.jpg
```

---

## Part 6 - Post-Processing Hooks

```python
class PostProcessor(Protocol):
    def process(self, media: DownloadedMedia) -> DownloadedMedia: ...
```

### `TranscriptionHook`

Requires `llm-core[whisper]`. Finds `media.video_file` (or `audio_file`), runs
`WhisperTranscriber.transcribe()`, populates `media.transcript`. No-op if no video/audio
file is present.

### `LanguageDetectionHook`

Requires `py3langid`. Runs on `media.caption + (media.transcript or "")`, populates
`media.language`. No-op if both are empty.

Both hooks are instantiated in the `DownloadRouter` constructor based on config flags.
They can also be instantiated standalone by library consumers who don't use the router.

---

## Part 7 - Config and Params

Following the `python-project-template` two-layer pattern precisely.

### Config layer (`config/downloader_config.py`)

Pure Pydantic, no I/O:

```python
class ProvidersConfig(BaseModelKwargs):
    instagram_enabled: bool = True
    video_enabled: bool = True          # yt-dlp
    web_recipe_enabled: bool = True
    transcription_enabled: bool = False # requires llm-core[whisper]
    language_detection_enabled: bool = False

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

### Paths layer (`params/downloader_paths.py`)

```python
class DownloaderPaths:
    def __init__(self, env_type: EnvType) -> None:
        self.env_type = env_type
        self.load_config()

    def load_common_config_pre(self) -> None:
        self.src_fol       = Path(social_media_downloader.__file__).parent
        self.root_fol      = self.src_fol.parents[1]
        self.data_fol      = self.root_fol / "data"
        self.cache_fol     = self.root_fol / "cache"
        self.media_fol     = self.data_fol / "media"    # passed to MediaStorage
        self.db_fp         = self.data_fol / "downloads.db"

    def load_config(self) -> None:
        self.load_common_config_pre()
        match self.env_type.location:
            case EnvLocationType.LOCAL:
                self.load_local_config()
            case EnvLocationType.RENDER:
                self.load_render_config()
            case _:
                raise UnknownEnvLocationError(self.env_type.location)

    def load_local_config(self) -> None:
        pass    # defaults are fine for local

    def load_render_config(self) -> None:
        pass    # no Render deployment planned; placeholder
```

### Params layer (`params/downloader_params.py`)

```python
class DownloaderParams(metaclass=Singleton):
    def __init__(self) -> None:
        self.set_env_type()

    def set_env_type(self, env_type: EnvType | None = None) -> None:
        self.env_type = env_type or EnvType.from_env_var()
        self.load_config()

    def load_config(self) -> None:
        self.paths = DownloaderPaths(env_type=self.env_type)
        self.providers = ProvidersParams(env_type=self.env_type)
        self.service = ServiceParams(env_type=self.env_type)

    def to_config(self) -> DownloaderConfig:
        return DownloaderConfig(
            db_path=self.paths.db_fp,
            media_base_dir=self.paths.media_fol,
            providers=self.providers.to_config(),
            service=self.service.to_config(),
        )


def get_downloader_params() -> DownloaderParams:
    return DownloaderParams()
```

`ProvidersParams` and `ServiceParams` follow the same single-arg `env_type` pattern
with `_load_common_params()` / `_load_dev_params()` / `_load_prod_params()` dispatch.

---

## Part 8 - Service Wrapper

### `create_app()`

```python
def create_app(config: DownloaderConfig | None = None) -> FastAPI:
    config = config or get_downloader_params().to_config()
    app = FastAPI(
        title="social-media-downloader",
        docs_url=None,
        redoc_url=None,
        openapi_url=None,       # internal service, no docs in prod
        lifespan=_lifespan,
    )
    app.state.config = config
    # Minimal middleware: request IDs and logging only (no auth, no CORS)
    app.add_middleware(RequestLoggingMiddleware)     # from fastapi-tools
    app.add_middleware(RequestIDMiddleware)          # from fastapi-tools
    app.include_router(health_router)               # from fastapi-tools
    app.include_router(sync_router)
    app.include_router(queue_router)
    return app

# Module-level instance for uvicorn
app = create_app()
```

Run as:
```
uvicorn social_media_downloader.webapp.app:app --host 127.0.0.1 --port 8010
```

Not in Cloudflare tunnel config - loopback only.

### `lifespan.py`

```python
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

    # Download router (assembles providers based on config)
    dl_router = build_router(config, storage)
    app.state.dl_router = dl_router

    # Background worker
    worker_task = asyncio.create_task(run_worker(db, dl_router))
    app.state.worker_task = worker_task

    yield

    worker_task.cancel()
    with suppress(asyncio.CancelledError):
        await worker_task
```

### `worker.py`

```python
async def run_worker(db: DownloadDBService, router: DownloadRouter) -> None:
    """Poll for pending jobs and process them one at a time."""
    # On startup: reset any jobs stuck in RUNNING (crash recovery)
    await db.reset_running_jobs()

    while True:
        job = await db.claim_next_pending_job()
        if job is None:
            await asyncio.sleep(2.0)
            continue
        try:
            result = await asyncio.to_thread(router.download, job.url, ...)
            await db.complete_job(job.id, result)
        except Exception as e:
            lg.exception(f"Job {job.id} failed: {e}")
            await db.fail_job(job.id, str(e))
```

`claim_next_pending_job()` uses a single `UPDATE ... SET status='running' WHERE id = (SELECT id FROM download_jobs WHERE status='pending' LIMIT 1) RETURNING *` - atomic under SQLite's serialised write lock, no race condition possible.

### Sync endpoint

```python
# POST /download  - blocks until complete

class DownloadRequest(BaseModel):
    url: str
    download_video: bool = True
    transcribe: bool = False
    detect_language: bool = False

@router.post("/download", response_model=DownloadJobRead)
async def download_sync(body: DownloadRequest, request: Request) -> DownloadJobRead:
    db: DownloadDBService = request.app.state.db
    dl_router: DownloadRouter = request.app.state.dl_router

    # Return existing job if already downloaded
    existing = await db.find_by_url(body.url)
    if existing and existing.status == JobStatus.DONE:
        return existing

    job = await db.create_job(body.url)
    try:
        result = await asyncio.to_thread(dl_router.download, body.url, ...)
        return await db.complete_job(job.id, result)
    except Exception as e:
        return await db.fail_job(job.id, str(e))
```

### Queue endpoints

```python
# POST /jobs    - enqueue, return immediately
# GET  /jobs/{id} - poll status + result

@router.post("/jobs", status_code=202, response_model=JobCreatedResponse)
async def enqueue(body: DownloadRequest, request: Request) -> JobCreatedResponse:
    db: DownloadDBService = request.app.state.db
    existing = await db.find_by_url(body.url)
    if existing:
        return JobCreatedResponse(job_id=existing.id, already_known=True)
    job = await db.create_job(body.url)
    return JobCreatedResponse(job_id=job.id, already_known=False)

@router.get("/jobs/{job_id}", response_model=DownloadJobRead)
async def get_job(job_id: str, request: Request) -> DownloadJobRead:
    db: DownloadDBService = request.app.state.db
    job = await db.get_job(job_id)
    if job is None:
        raise HTTPException(status_code=404, detail="Job not found")
    return job
```

---

## Part 9 - Source Expansion Roadmap

### Phase 1 - bootstrap

Extract `InstaDownloader` from recipinator/recipamatic verbatim (no login variant).
Add `YtDlpDownloader` immediately - public TikTok and YouTube require no auth.
Wire `UrlDetector` and `DownloadRouter`.

### Phase 2 - recipe web

`WebRecipeDownloader`: `recipe-scrapers` for structured schema.org markup (handles
BBC Food, AllRecipes, NYT Cooking, hundreds more). Falls back to `trafilatura` for
plain article extraction when no recipe schema is present.

`LanguageDetectionHook` and `TranscriptionHook` as optional post-processors.

### Phase 3 - extended social

Pinterest via `gallery-dl`. Twitter/X image galleries (video already handled by
yt-dlp in Phase 1). Reddit image galleries.

---

## Part 10 - Remaining Pain Points

**`asyncio.to_thread` for downloads is unavoidable.** Both `instaloader` and
`yt-dlp` are sync libraries. Wrapping them in `to_thread` is correct and honest
about what is happening. The DB layer uses proper async (SQLAlchemy async engine)
and does not need this workaround.

**SQLite single-writer limit.** With the worker loop and the sync endpoint both
writing, enable WAL mode unconditionally in `init_db()`:
`await session.execute(text("PRAGMA journal_mode=WAL"))`. This allows concurrent
readers and a single writer without blocking.

**yt-dlp format string.** Exposed as `DownloaderConfig.yt_dlp_format` for easy
tuning. The default covers the common case; age-gated or private content is out of
scope.

**Instagram public API stability.** Instaloader works against public profiles today
without login. Platform changes can break this; instaloader is actively maintained
and typically patches quickly. Pin the version and monitor the changelog.

**`jsons` library.** Both recipinator and recipamatic use it for dataclass
serialization. With the move to SQLAlchemy + Pydantic v2, `jsons` is no longer
needed anywhere in this service. Good housekeeping to drop it.

**Internal package refs.** All internal packages (`fastapi-tools`, `llm-core`)
are referenced via git tags:
```
fastapi-tools @ git+https://github.com/Pitrified/fastapi-tools@v0.1.0
llm-core      @ git+https://github.com/Pitrified/llm-core@v0.1.0
```
`uv` resolves these correctly. Tag before consuming.

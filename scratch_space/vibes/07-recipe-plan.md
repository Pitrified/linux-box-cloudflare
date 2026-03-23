# The Recipe

## Overview

we have as libraries ready to use:

- `llm-core`
- `fastapi-tools`
- `media-downloader`

we have existing recipe-related projects:

- `recipamatic`
- `recipinator`
- `cookbook` - Personal static recipe site in Italian. Jekyll + GitHub Pages. Live at `pitrified.github.io/cookbook`.

between `recipamatic` and `recipinator`, we have as features:

- a recipe model (might differ slightly)
- a recipe ingestion pipeline (scraping, downloading, metadata extraction)
- a recipe CRUD service which lets the user _sort_ the recipes based on what they want to cook soon, and a _search_ interface to find recipes based on ingredients, tags, etc.
- a way to dictate recipes while cooking, and then building a clean recipe leveraging timestamped voice notes
- ??? possibly some more features that i do not remember right now

note: the actual tech stack for the three existing projects is not relevant. we want to update to the new libraries.

focus on a _functional_ feature dive: what was done in the past that could be reimplemented with the new tech?

## Functional overview

### 1. Recipe data model

All three projects converge on the same core schema. The canonical shape (from `recipamatic` + `cookbook`) is:

- **`RecipeCore`**
  - `name` / `title`
  - `serves` (serving size string)
  - `category` / `course` - one of 8 Italian meal-course buckets (`pani`, `antipasti`, `primi`, `secondi`, `fritti`, `contorni`, `dolci`, `alcol`)
  - `author`
  - `source` - enum: `instagram` | `voice_note` | `manual`
  - `user_id`, `is_public`
  - `notes: list[str]` - freeform recipe notes
  - `excerpt` - short description for list/card views
  - Optional attribution: `inspiration.name`, `.text`, `.link`
  - Optional finish image

- **`Preparation`** (named sub-section; `preparation_name` is optional for single-section recipes)
  - `ingredients: list[Ingredient]` - each has `name` + `quantity` (amount + unit as a single string)
  - `steps: list[Step]` - each has `type` (`text` or `image`) + `instruction` / image metadata

- **`Tag`** (from `recipinator`) - `name` + `usefulness` score; linked to recipes via `RecipeTagLink` with `confidence` + `origin` (designed for AI-assigned tags)

- **`Author`** (from `recipinator`) - `username`, `userid`, `full_name`, `biography`, `page_link` - a separate entity when ingesting from Instagram

- **`User`** (from `recipamatic`) - `id` (Google sub), `email`, `name`, `picture`, `role` (`admin`/`user`)

---

### 2. Instagram ingestion pipeline

Implemented (working) in both `recipamatic` and `recipinator`, with broadly the same approach:

1. Accept a post shortcode (URL or raw code)
2. `InstaLoader` wraps the `instaloader` library; auth via saved session; downloads post: caption, title, author profile, hashtags, thumbnail JPEG, video MP4
3. Deduplicate by shortcode; cache to disk at `data/ig/posts/<shortcode>/` (JSON + media files)
4. Detect caption language via `py3langid`
5. Feed caption text into `RecipeCoreTranscriber` (LLM step below)

Key difference: `recipinator` persists results to SQLite; `recipamatic` persists to flat JSON files.

---

### 3. LLM-based recipe parsing

Implemented (working) in `recipamatic`:

- **`RecipeCoreTranscriber`** - LangChain chain using GPT-4o-mini (`with_structured_output(RecipeCore)`, temp=0.2); system prompt instructs to preserve original language and combine related steps into named preparations. Input: any free text (Instagram caption, voice transcript, manual paste). Output: structured `RecipeCore`.

- **`RecipeCoreEditor`** - given an old recipe + a step reference + NL correction instructions, returns a corrected `RecipeCore` with exactly that step changed and everything else preserved.

- **`SectionIdxFinder`** - interprets NL location queries ("step 2 of the sauce preparation") into a `(preparation_idx, step_idx)` tuple; used to locate the target before calling the editor.

Planned but not built in `recipinator`: AI tag extraction wired to the `RecipeTagLink.confidence` / `origin` columns.

---

### 4. Video / audio transcription

Prototyped in `recipinator` (Jupyter notebook only); working end-to-end in `recipamatic`:

- **`Whisperer`** wraps the local `openai-whisper` model (configurable size: base / medium / large); accepts a file path or raw audio bytes; multi-language
- In `recipamatic`: the full flow is `data/ig/posts/<shortcode>/p_video_url.mp4` → Whisper → transcript → combined with caption → `RecipeCoreTranscriber` → `RecipeCore`

---

### 5. Live cooking voice notes

Unique to `recipamatic`; fully working:

- **`RecipeNote`** model - a timestamped cooking session log: `start_time` + `list[Note(text, timestamp)]` where timestamps are relative to session start
- `to_string()` renders as `MM:SS: note text` - designed to be fed back to the LLM to build a clean recipe from the dictation
- **Browser flow**: `AudioRecorder.svelte` uses the browser `MediaRecorder` API to capture mic audio, submits `audio/webm` blobs via multipart `POST`; the backend Whisperer transcribes each clip and appends a new `Note`
- **API**: `POST /recipe_note/create` → `POST /recipe_note/{code}/update` (audio upload) → `GET /recipe_note/{code}/show`
- Recipe note codes are timestamp strings (`20250413_120000`)

The intended next step (mentioned in docs, not yet built): feed the full `RecipeNote.to_string()` into `RecipeCoreTranscriber` to produce a clean structured recipe.

---

### 6. Recipe CRUD & access control

Working across both projects (combined):

| Operation | recipamatic | recipinator |
|--|--|--|
| Create (manual) | yes (via API) | yes (via API) |
| Create (from Instagram) | yes | yes |
| Create (from voice note) | yes | - |
| Read single | yes | yes |
| Read list | yes | yes (paginated) |
| Update (LLM-powered step edit) | yes | prototype only |
| Delete | **not implemented** | **not implemented** |
| Public/private toggle | yes | - |
| User ownership | yes | - |

Auth: Google OAuth → HS256 JWT (30-day expiry) in `recipamatic`. `recipinator` has no auth.

---

### 7. Sort / "cook soon" queue

Unique to `recipinator`; fully working:

- Every recipe has a `sort_index` integer representing priority in the "what to cook" queue
- Frontend `RecipeSorter` uses `react-beautiful-dnd` for drag-and-drop reordering
- `POST /recipes/shuffle` persists swaps to SQLite
- `recipamatic`'s `plan.md` identifies "sort recipes based on what they want to cook soon" as a desired feature but it is not implemented there

---

### 8. Search & discovery

Not yet implemented server-side in either project; the scaffolding exists:

- `recipinator` has a `SearchBox` component (text + tag filter buttons) that re-fetches `/recipes/` on change, but no actual server-side filtering is wired
- `recipinator` has ChromaDB (`langchain-chroma`) + Sentence Transformers set up for vector similarity search (prototype notebooks only, not exposed via API)
- `recipinator`'s `RecipeTagLink` has `confidence` + `origin` columns ready for AI-assigned tags; creation pipeline not built
- `recipamatic`'s `plan.md` lists "full-text search, filter by ingredient/tag/time, recommendations" as a top future improvement

---

### 9. Frontend

Two separate frontends (SvelteKit in `recipamatic`; React + Vite in `recipinator`). Combined feature set:

| Screen | Where |
|--|--|
| Recipe list / card grid | both |
| Full recipe detail (preparations, ingredients, steps) | both |
| "My recipes" (auth-gated, shows only user's recipes) | recipamatic |
| Live voice note session (audio recorder embedded in page) | recipamatic |
| Drag-and-drop recipe browser with sort persistence | recipinator |
| Search bar + tag filter buttons | recipinator |
| Google OAuth login / profile page | recipinator |

---

### 10. Static personal cookbook (`cookbook`)

A separate Jekyll + GitHub Pages site for the personal Italian recipe archive. Features:

- 8 Italian meal courses (`pani`, `antipasti`, `primi`, `secondi`, `fritti`, `contorni`, `dolci`, `alcol`) as collections with hand-ordered display
- Recipe frontmatter: `category`, `author`, `serves`, `excerpt`, `imagefinished`, `inspiration`/attribution, multi-preparation ingredients + step lists, `notes`, `seealso` cross-links
- Step types: `text` (prose instruction) and `image` (inline step photo)
- ~20 actual recipes currently published (in Italian)
- `scripts/add_new.py` CLI: scans `~/Pictures/ricette/new/<category>/<name>/finito.jpg`, copies assets, generates dated post file from a template

This is a _publishing target_, not a CRUD app. Recipes are authored manually as Markdown and pushed to GitHub.

---

### Summary: what is worth reimplementing

| Feature | Maturity | Reuse verdict |
|--|--|--|
| Recipe data model (`RecipeCore` + `Preparation` + `Ingredient` + `Step`) | solid, consistent across all projects | port to Pydantic `BaseModel`, keep schema |
| Instagram scrape → cache → LLM parse | working end-to-end | reimplement against `media-downloader` + `llm-core` |
| `RecipeCoreTranscriber` (text → structured recipe) | working | reimplement with `llm-core` `StructuredLLMChain` |
| `RecipeCoreEditor` + `SectionIdxFinder` (NL step edit) | working | reimplement with `llm-core` |
| Live voice note session (dictation while cooking) | working | reimplement; audio upload + Whisper transcription via `llm-core` |
| Voice note → `RecipeCoreTranscriber` → recipe | designed, not wired | implement the missing bridge |
| "cook soon" sort queue with drag-and-drop | working (recipinator) | reimplement |
| Full-text / semantic search | not implemented anywhere | implement fresh with `llm-core` vector store |
| AI tag extraction + `confidence`/`origin` | data model designed, pipeline not built | implement fresh |
| Google OAuth + JWT auth + recipe ownership | working (recipamatic) | reuse pattern from `python-project-template` |
| Static cookbook publishing | separate concern | keep as-is; add an export-to-Jekyll script |

## Brainstorm

### Concerns to split

Before comparing layouts, it helps to name the distinct concerns clearly:

| Concern | Notes |
|--|--|
| **A. Recipe data model + validation** | Pydantic schema; shared by everyone |
| **B. Persistent storage** | CRUD, search index, sort state |
| **C. Instagram ingestion** | scrape → download → cache |
| **D. Transcription** | Whisper; applies to both IG video and live mic audio |
| **E. LLM parsing + editing** | text/transcript → structured recipe; NL step edit |
| **F. AI tag extraction** | run LLM over recipe, produce `Tag[]` with confidence |
| **G. Voice note session** | live dictation: create → append audio clips → freeze |
| **H. Sort queue** | drag-and-drop cook-soon ordering |
| **I. Semantic search** | vector store + embeddings |
| **J. Auth / user management** | Google OAuth → JWT; recipe ownership; public/private |
| **K. HTTP API** | endpoints consumed by any frontend |
| **L. Frontend** | the actual user-facing UI |
| **M. Cookbook export** | Jekyll markdown generation from a recipe record |

Concerns A-J are purely backend. K is the API surface. L and M are clients.

The key architectural question is: how do you group A-K into deployable units?

---

### Option 1: Single monolithic repo + single FastAPI app

Everything (ingestion, transcription, LLM pipelines, storage, auth, API) lives in one Python package with a single FastAPI app, fronted by a single frontend (SvelteKit or React).

**Pros:**
- Simplest possible dev setup: one `uv run uvicorn` command
- No inter-service latency; all concerns share in-process state and config
- Single database connection, single Alembic migration history
- Easiest to refactor - move code between modules freely
- Cheapest to host: one dyno / one VM process
- Easier to reason about: one log stream, one crash = everything crashes together (which is fine for personal use)

**Cons:**
- The "slow" concerns (Whisper transcription, LLM calls, IG scraping) would block the FastAPI event loop unless carefully offloaded to a background worker / thread pool - this requires discipline inside a monolith
- As features accumulate the single app grows harder to navigate
- Deploys all-or-nothing: a broken LLM pipeline can break recipe browsing

**Verdict:** Strong default for a personal project. The async concern is real but manageable with a background task queue (FastAPI `BackgroundTasks` or a lightweight queue like `rq`).

---

### Option 2: Monorepo, separated backend services

One Git repo, multiple deployable Python packages under a common structure:

```
recipe/
  packages/
    recipe-core/      # A: shared Pydantic models only (no deps)
    recipe-store/     # B + K: storage + CRUD API (FastAPI)
    recipe-ingest/    # C + D + E + F: ingestion worker (runs headless)
    recipe-voice/     # G + D: voice note session service
    recipe-search/    # I: vector store + semantic search API
  frontend/           # L
```

`recipe-store` is the only service exposed externally. `recipe-ingest`, `recipe-voice`, `recipe-search` are internal workers that write to the shared DB and are triggered by `recipe-store` (e.g. via a job queue or direct HTTP call to localhost).

**Pros:**
- Clear separation: slow async work (scraping, Whisper, LLM) is isolated from the read/browse API
- Each service can be restarted/redeployed independently
- `recipe-core` as a shared library pins the data model, preventing drift
- Natural fit with `llm-core` + `media-downloader` design patterns (each package has its own `Params` singleton)

**Cons:**
- More infra to manage: multiple uvicorn processes, a job queue or message bus to coordinate them, shared DB needs to be visible to all services
- Cross-service calls add latency and failure modes ("ingest service is down, why can't I add recipes?")
- Overkill for personal use: the real throughput is low (one user, a few recipes per week)
- Shared `recipe-core` package creates a versioning/update discipline requirement; changing the schema requires coordinating all consumers

**Verdict:** The right shape for a team product. For a solo personal project, the coordination overhead outweighs the isolation benefit.

---

### Option 3: Monorepo, single backend + background worker process

One Git repo, one FastAPI app, but heavy async concerns run in a separate worker process that shares the same codebase:

```
recipe/
  src/recipe/
    api/          # K: FastAPI routers
    store/        # B: DB models + CRUD
    ingest/       # C + D + E + F: ingestion pipeline
    voice/        # G + D: voice notes
    search/       # I: vector store
    auth/         # J
    models/       # A: Pydantic schemas
  worker/
    worker.py     # reads a job queue; calls ingest/voice/search functions
  frontend/       # L
```

The FastAPI app enqueues slow jobs (IG ingest, Whisper, LLM tag extraction) to a lightweight queue (e.g. `rq` backed by Redis, or even `arq` which uses asyncio). The worker process dequeues and executes them. The API serves results from the DB once the job completes; the frontend polls or uses a websocket for progress.

**Pros:**
- API stays responsive: slow work never blocks a request handler
- Still one codebase; no package versioning dance; full code reuse
- One DB, one migration history, one config system
- Worker and API can be on the same machine (personal use = one VM)
- Clean mental model: "API = thin orchestrator + reads; worker = heavy async processing"
- Scales naturally: add more worker processes if needed

**Cons:**
- Requires running two processes (api + worker) and a queue backend (Redis or similar)
- Slightly more complex local dev setup (a `Makefile` or `docker-compose` helps)
- Job failure/retry handling needs implementation (though `rq` provides this)
- Still one deploy unit conceptually - a breaking change affects both

**Verdict:** Best balance for a personal project that intends to grow. The two-process model is the natural fit for `fastapi-tools` + background workers. Redis is already a reasonable dependency given this service set.

---

### Option 4: Thin API backend + rich logic in `media-downloader`

Treat `media-downloader` as the primary library for concerns C + D, adding recipe-specific post-processing hooks. Build `recipe` as a thin FastAPI app that:

- delegates all download / transcription to `media-downloader`
- delegates all LLM pipelines to `llm-core`
- owns only the recipe data model, storage, sort, auth

```
recipe/     # thin app: models + storage + auth + API
  ↓ uses
media-downloader/   # C + D (IG scraping, Whisper transcription)
llm-core/           # E + F + I (LLM parsing, tags, embeddings)
```

**Pros:**
- Maximises reuse of already-built, already-tested libraries
- `recipe` repo stays narrow in scope
- `media-downloader` improvements (new sources, better transcription) flow into recipe automatically
- Cleanest dependency graph

**Cons:**
- `media-downloader` currently has no recipe-specific concept: fitting the ingestion pipeline in means either forking it (defeats the purpose), adding recipe hooks to a general-purpose library (wrong abstraction), or accepting an awkward adapter layer
- LLM parsing (concern E) is purely recipe-specific logic; it cannot live in `llm-core` without polluting it
- `media-downloader` + `llm-core` have their own release cadence; a breaking change there can block recipe development
- Cross-repo dev cycles (change `media-downloader`, bump version, update `recipe`) are friction even with `uv` path dependencies

**Verdict:** Good inspiration for the dependency structure but wrong to push recipe-specific elaboration into the general-purpose libraries. Use `media-downloader` as a dependency for steps C+D, not as the home for recipe logic.

---

### Option 5: Small separate repos (microservices by feature)

Full split - each concern is its own Git repo + its own deployable service:

```
recipe-model          (A)
recipe-api            (B + K)
recipe-ingest         (C + D + E)
recipe-voice          (G + D)
recipe-search         (H + I)
recipe-frontend       (L)
```

**Pros:**
- Maximum isolation; each piece can evolve and be deployed independently
- Language/framework freedom per service (though in practice all Python here)

**Cons:**
- For a personal project with one developer and low traffic this is massive overhead
- 6 repos = 6 CI pipelines, 6 deployment configs, 6 sets of dependencies to keep in sync
- The shared recipe model (A) becomes a published package that every repo pins; schema evolution is painful
- Cross-cutting concerns like auth and common error handling get duplicated or need yet another shared package
- Dev environment setup becomes complex (need all services running locally to test end-to-end)

**Verdict:** Reject. The operational overhead is not justified for personal use.

---

### Option 6: Monorepo + Telegram bot as primary UI (no web frontend initially)

Swap the web frontend for a Telegram bot (using `tg-central-hub-bot` patterns) as the primary interaction layer, at least initially:

- Add IG URL → bot command → bot replies with parsed recipe card
- Voice messages sent to the bot → Whisper → recipe note session → "finish" command → clean recipe
- Sort queue managed via inline keyboard buttons
- Search via bot commands

A web frontend can be added later without changing the backend.

**Pros:**
- Zero frontend build/deploy overhead; Telegram handles the UI
- Voice input is native on mobile (Telegram voice messages)
- Auth is implicit (Telegram user ID)
- `tg-central-hub-bot` infra is already built and tested
- Ideal for quick personal prototyping

**Cons:**
- Telegram bot UX is clunky for browsing/sorting a large recipe list
- Drag-and-drop sort queue is impossible in a bot
- The recipe detail view (multi-preparation, ingredients + steps) is hard to render in a chat message
- Not a web app - no shareable links, no public recipe browsing
- Couples the interaction layer to Telegram forever unless the backend API is kept clean

**Verdict:** Excellent for the ingestion and voice-note flows as a fast prototype. Pair with Option 3's backend and add a web frontend later when needed.

---

### Preferred direction

Given the context (personal project, one developer, goal of consolidating two existing half-baked apps into one clean implementation using the new libraries), the recommended approach is:

**Option 3 (monorepo, single backend + background worker) + Option 6 (Telegram bot as the initial UI)**

Concretely:

1. New repo `recipe` (or keep under `recipamatic`) using `python-project-template` scaffold -> `kit-hub` new repo
2. Backend: FastAPI app (Option 3 structure) with SQLite (upgradeable to Postgres) -> ok
3. Heavy work (IG scrape, Whisper, LLM) run via `arq` / `rq` background worker in the same codebase; worker triggered by API calls -> ok
4. `media-downloader` used as a dependency for IG download + Whisper; recipe-specific LLM logic stays in `recipe` -> ok
5. `llm-core` `StructuredLLMChain` for transcription + editing + tag extraction -> ok
6. Telegram bot (`tg-central-hub-bot`) as the first UI: paste IG URL, receive recipe; send voice, get transcript -> ok
7. Simple web frontend (SvelteKit) added later for browse/sort/search flows -> ok, evaluate if we can limit this to fastapi templates or if a full SPA is needed. drag and drop is cool but not a must-have, we can explore other UI patterns for the sort queue if it saves a lot of frontend work.

Key decisions to make before starting:
- **Which queue**: `arq` (asyncio-native, no Redis required if using in-process) vs `rq` (simpler, Redis required) vs `FastAPI BackgroundTasks` (simplest, no persistence - fine if the server doesn't restart mid-job) -> arq, in process for simplicity, with the option to switch to Redis later if needed
- **Database**: SQLite with SQLModel + Alembic from day 1 (avoid the flat-JSON trap of `recipamatic`) -> ok
- **Recipe code / primary key**: shortcode for IG recipes; UUID for manual/voice recipes -> ok
- **Frontend timing**: defer until the core ingestion + voice + LLM pipeline works end-to-end -> ok

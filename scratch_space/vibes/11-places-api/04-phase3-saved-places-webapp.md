# Phase 3 - Build `saved-places` webapp

**Status:** not started  
**Depends on:** Phase 1 (google-maps-tools >= 1.3, 1.5 complete)  
**Blocks:** nothing

Create a personal webapp for browsing, organizing, and annotating Google Maps
saved places. Built on FastAPI + HTMX (via `fastapi-tools`), SQLAlchemy for
storage, and `google-maps-tools` for ingestion and enrichment.

---

## 3.1 - Repo bootstrap

**Status:** not started

- Create `saved-places` from `python-project-template` via `rename-project`.
- Package name: `saved_places`. Python >= 3.14.
- Dependencies: `fastapi-tools`, `google-maps-tools` (local path dep),
  `sqlalchemy`, `alembic`, `loguru`, `pydantic`.
- Configure `~/cred/saved-places/.env` with `GOOGLE_MAPS_API_KEY` and
  `SESSION_SECRET_KEY`.
- Verify scaffold: `uv run pytest && uv run ruff check . && uv run pyright`.

---

## 3.2 - Database layer

**Status:** not started  
**Depends on:** 3.1

Module: `src/saved_places/db/`

Follow the `kit-hub` SQLAlchemy + Alembic pattern.

**3.2a - ORM models**

| Table | Key columns |
| ------------ | ---------------------------------------------------------------- |
| `places` | `id` (PK), `place_id` (unique), `name`, `formatted_address`, `lat`, `lng`, `types` (JSON), `rating`, `price_level`, `editorial_summary`, `website`, `phone`, `opening_hours` (JSON), `raw_json` (JSON), `created_at`, `updated_at` |
| `saved_lists` | `id`, `name`, `source_file`, `imported_at` |
| `list_membership` | `list_id` (FK), `place_id` (FK), `user_note` |
| `tags` | `id`, `name` |
| `place_tags` | `place_id` (FK), `tag_id` (FK) |
| `visits` | `id`, `place_id` (FK), `visited_at`, `note` |

**3.2b - Alembic setup**
- `alembic init alembic` inside project root.
- Initial migration generating all tables above.

**3.2c - CRUD service**
- `PlaceDBService` with methods:
  - `upsert_place(place: Place) -> PlaceRow`
  - `get_place(place_id: str) -> PlaceRow | None`
  - `list_places(list_id?, tag_ids?, visited?) -> list[PlaceRow]`
  - `set_tags(place_id, tag_names: list[str])`
  - `add_visit(place_id, visited_at, note?)`
- `SavedListDBService` with `upsert_list(name, places: list[Place]) -> SavedListRow`.

---

## 3.3 - Ingestion flow

**Status:** not started  
**Depends on:** 3.2, Phase 1 (1.3 + 1.5)

Allow importing Google Takeout exports via the webapp.

**3.3a - Import endpoint**
- `POST /import` accepts a multipart file upload (CSV or GeoJSON).
- Parses with `google_maps_tools.takeout.parse_takeout`.
- Enqueues enrichment (calls `enrich_saved_places`) in a background task
  (FastAPI `BackgroundTasks`).
- Returns an import job ID; frontend polls `GET /import/{job_id}` for status.

**3.3b - Import status tracking**
- In-memory job store (dict) for simplicity; upgrade to DB row if needed.
- States: `pending` -> `enriching` -> `done` / `error`.
- Progress: `enriched_count / total_count`.

**3.3c - Re-import / update**
- A second import of the same list name updates existing entries by `place_id`
  (upsert) and adds any new ones.

---

## 3.4 - Browse and search UI

**Status:** not started  
**Depends on:** 3.2

Module: `src/saved_places/webapp/routers/places.py`

**3.4a - Place list view**
- `GET /places` renders `templates/places/list.html` with Jinja2.
- HTMX-powered filter controls (no page reload):
  - Filter by saved list (`?list_id=`)
  - Filter by type (e.g. restaurant, museum)
  - Filter by neighbourhood (extracted from `address_components`)
  - Filter by rating range
  - Filter by visited / not-visited

**3.4b - Place detail view**
- `GET /places/{place_id}` renders `templates/places/detail.html`.
- Shows all `Place` fields, embedded Google Maps iframe, visit log, tags,
  and user note.
- Edit form for note, tags, visited toggle (HTMX POST).

**3.4c - Search**
- `GET /places/search?q=` performs case-insensitive substring search on
  `name` + `formatted_address` + `editorial_summary`.
- Returns HTMX partial (`hx-target="#results"`).

**3.4d - Neighbourhood view**
- `GET /neighbourhoods` groups places by locality address component.
- Shows each neighbourhood as a card with place count and a mini-map snippet.

---

## 3.5 - Tagging, notes, and visit tracking

**Status:** not started  
**Depends on:** 3.2, 3.4

**3.5a - Tag management**
- `POST /places/{place_id}/tags` (HTMX form) adds/removes tags.
- `GET /tags` lists all tags with place counts.
- Filter in place list view by tag.

**3.5b - User note editing**
- Inline HTMX edit form on place detail page.
- `PATCH /places/{place_id}/note` updates `list_membership.user_note`.

**3.5c - Visit log**
- `POST /places/{place_id}/visits` records a visit with optional date and note.
- Visit history shown on detail page, newest first.
- `?visited=true/false` filter in list view.

---

## 3.6 - Optional LLM features

**Status:** not started  
**Depends on:** 3.2, `llm-core`

Stretch goals - implement only after core CRUD + UI is stable.

**3.6a - Natural-language search**
- Embed place descriptions via `llm-core` embeddings; store in Chroma.
- `GET /places/semantic-search?q=` returns semantically similar places.

**3.6b - "Plan a day" assistant**
- User selects a neighbourhood; LLM suggests an ordered itinerary for the day.
- Uses `StructuredLLMChain` from `llm-core` with place data as context.

---

## 3.7 - Deployment and docs

**Status:** not started

- `render.yaml` for Render.com deployment (same pattern as `kit-hub`).
- Write `docs/library/ingestion.md` and `docs/library/browse_ui.md`.
- Full verification: `uv run pytest && uv run ruff check . && uv run pyright`.

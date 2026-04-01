# Places core tracking

High-level tracking of places-related projects in the linux-box ecosystem.

Core analysis: [00-places-overview.md](./00-places-overview.md)

---

## Phase status

| Phase | Description | Status | Sub-plan |
| ----- | ----------- | ------ | -------- |
| 1 | Create `google-maps-tools` library | done | [02-phase1-google-maps-tools.md](./02-phase1-google-maps-tools.md) |
| 2 | Rebuild `trip-me-up` on `google-maps-tools` | not started | [03-phase2-trip-me-up-rebuild.md](./03-phase2-trip-me-up-rebuild.md) |
| 3 | Build `saved-places` webapp | not started | [04-phase3-saved-places-webapp.md](./04-phase3-saved-places-webapp.md) |

---

## Phase 1 - `google-maps-tools` sub-tasks

| Task | Description | Status |
| ---- | ----------- | ------ |
| 1.1 | Repo bootstrap | done |
| 1.2 | Canonical place data models | done |
| 1.3 | Google Takeout parser (CSV + GeoJSON) | done |
| 1.4 | HTTP caching layer | done |
| 1.5 | Google Places API client | done |
| 1.6 | Geo utilities (haversine, clustering) | done |
| 1.7 | Params / config wiring | done |
| 1.8 | Docs and verification | done |

## Phase 2 - `trip-me-up` rebuild sub-tasks

| Task | Description | Status |
| ---- | ----------- | ------ |
| 2.1 | Toolchain migration (uv, ruff, pyright, Python 3.14) | not started |
| 2.2 | Replace raw API calls and dict-passing | not started |
| 2.3 | Distance matrix and neighbourhood layout | not started |
| 2.4 | Itinerary planner | not started |
| 2.5 | Optional CLI | not started |
| 2.6 | Verification | not started |

## Phase 3 - `saved-places` webapp sub-tasks

| Task | Description | Status |
| ---- | ----------- | ------ |
| 3.1 | Repo bootstrap | not started |
| 3.2 | Database layer (SQLAlchemy + Alembic) | not started |
| 3.3 | Ingestion flow (import endpoint, status tracking) | not started |
| 3.4 | Browse and search UI | not started |
| 3.5 | Tagging, notes, and visit tracking | not started |
| 3.6 | Optional LLM features | not started |
| 3.7 | Deployment and docs | not started |

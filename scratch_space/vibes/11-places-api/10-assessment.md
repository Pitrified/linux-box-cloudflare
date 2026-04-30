# Assess `places-tools` project

## Overview

plan made in this folder
`scratch_space/vibes/11-places-api/*`
were implemented in repo
`places-tools`

This document tracks the state of the implementation against the original plan
and was updated after the follow-up clean-up pass that closed all Phase 1
gaps.

## Implementation status (post follow-up)

Phase 1 (`places-tools`) is now **complete and green**. All sub-tasks listed in
the plan are implemented, including the stretch goals (Places API New, async
clients, Distance Matrix). Phases 2 and 3 are still untouched and remain the
next deliverables.

### Phase 1 - sub-task by sub-task

| Sub-task | Plan ref | Status | Notes |
| -------- | -------- | ------ | ----- |
| 1.1 Repo bootstrap | [02-phase1 §1.1](./02-phase1-google-maps-tools.md) | done | Renamed to `places-tools`, uv + Python 3.14, deps in `pyproject.toml`. |
| 1.2 Data models | [§1.2](./02-phase1-google-maps-tools.md) | done | All seven models present in `src/places_tools/models/`. |
| 1.3 Takeout parser | [§1.3](./02-phase1-google-maps-tools.md) | done | `csv_parser.py`, `geojson_parser.py`, `parse_takeout.py`. CSV now extracts `saved_at` from `Created`/`Updated`/`Data di creazione`/`Aggiornato` columns and resolves `place_id` from URLs via `takeout/url_utils.py`. GeoJSON parser handles nested `properties.location.name` and multiple URL key variants. Tests under `tests/takeout/test_takeout.py`, `test_parsers.py`, and `test_url_utils.py`. |
| 1.4 HTTP caching layer | [§1.4](./02-phase1-google-maps-tools.md) | done | `src/places_tools/cache/cache_store.py` (`CacheStore[T]` generic, sha256-hashed filenames, JSON envelope with `created_at`, TTL via `ttl_seconds`) and `cache/place_caches.py` (`FindPlaceCache` keyed by query, `PlaceCache` keyed by `place_id` + sorted field set). Tests under `tests/cache/test_cache.py`. |
| 1.5 Places API client | [§1.5](./02-phase1-google-maps-tools.md) | done | `PlaceField` enum + `DEFAULT_FIELDS`, `FindPlaceClient`, `PlaceDetailsClient`, `enrich_saved_places`, plus stretch 1.5d (Places API New) implemented behind the `api_version` flag with field-mask translation in `places/parsing.py` + `_to_new_field_mask()` helper. Async variants `AsyncFindPlaceClient` and `AsyncPlaceDetailsClient` added. `enrich_saved_places` now returns a structured `EnrichResult(enriched, failed)` with `EnrichFailure(reason, detail)` entries. |
| 1.6 Geo utilities | [§1.6](./02-phase1-google-maps-tools.md) | done | `haversine`, `BoundingBox` + `filter_by_bbox`, `cluster_by_address`, `cluster_by_proximity` (now names neighbourhoods by dominant locality), and stretch 1.6d `geo/distance_matrix.py` (`DistanceMatrixClient` with `get_durations()` / `get_distances()`, `TravelMode = Literal["driving","walking","bicycling","transit"]`, `DistanceMatrixError`). |
| 1.7 Params / config wiring | [§1.7](./02-phase1-google-maps-tools.md) | done | `CacheParams` (`params/cache_params.py`) is wired into `PlacesToolsParams` and exposed both as `params.cache` and via `get_cache_params()`. Factories module (`places/factories.py`) builds sync and async clients straight from the singleton: `make_find_place_client`, `make_place_details_client`, `make_async_find_place_client`, `make_async_place_details_client`. |
| 1.8 Docs and verification | [§1.8](./02-phase1-google-maps-tools.md) | done | `docs/library/{cache,geo,models,places_api,takeout}.md` all describe the actual code; `places_api.md` covers async clients, factories, and the New API; `geo.md` documents Distance Matrix. Verification suite is green. |

### Verification suite status

Run on the current repo (`/home/pmn/ephem/places-tools`):

- `uv run pytest`: **121 passed**, 0 failed.
- `uv run ruff check .`: **All checks passed**.
- `uv run pyright`: **0 errors**, 0 warnings.

### Phase 2 / 3

Both phases remain untouched. `trip-me-up` still uses Poetry / Python 3.11 and
raw JSON dicts; the `saved-places` repo does not exist. None of the Phase 2
sub-tasks (toolchain migration, dict-to-model replacement, distance matrix
integration, itinerary planner, CLI) or Phase 3 sub-tasks (FastAPI bootstrap,
DB layer, ingestion, browse UI, tagging, LLM features, deployment) have been
started.

## Code quality assessment (post follow-up)

The codebase is now small, internally consistent, and follows the project
template conventions throughout.

### Strengths

- One-class-per-file model layout in `models/`, clean `BaseModel` subclasses.
- `PlaceField` is a `StrEnum` with a frozen `DEFAULT_FIELDS` set; the New API
  field-mask translation is centralised in `places/place_details_client.py` so
  callers never need to know which API version they are talking to.
- Clients use constructor-injected `httpx.Client`, which makes them trivial to
  unit-test with `MagicMock` and lets callers share connection pools across
  multiple clients.
- All long-lived clients are context managers (`__enter__` / `__exit__` for
  sync, `__aenter__` / `__aexit__` for async). Default sync client has a 10 s
  timeout and 3 transport-level retries via `httpx.HTTPTransport(retries=...)`.
- Custom exceptions (`PlaceNotFoundError`, `PlaceDetailsError`,
  `DistanceMatrixError`, `UnsupportedTakeoutFormatError`,
  `UnknownEnvLocationError`, `UnknownEnvStageError`) are used consistently.
- Geo clustering remains dependency-free.
- CSV parser handles English and Italian headers with a single normalization
  map and `utf-8-sig`; first non-empty match per canonical field wins so
  `Note` takes priority over `Comment` when both exist.
- `params/places_api_params.py` masks `api_key` as `[REDACTED]` in `__str__`
  and uses `SecretStr` internally. Same pattern in `params/cache_params.py`.
- `EnrichResult` makes batch failures observable (`reason`, `detail`) instead
  of being silently logged and dropped.

### Remaining nice-to-haves

These are not blockers; they are quality-of-life improvements to revisit when
Phase 2 / 3 starts to drive the requirements.

1. **End-to-end notebook.** `scratch_space/01_basic_usage.ipynb` (parse ->
   enrich -> cluster -> rich render) is still missing. The unit tests cover
   each stage in isolation, so an integration notebook is now a developer
   ergonomics improvement rather than a correctness gate.
2. **Shared test fixtures.** `_FakeResponse` and the `_mock_http_get` /
   `_mock_http_post` helpers are duplicated between `tests/places/` files.
   Pulling them into `tests/places/conftest.py` would reduce friction when
   adding more client tests.
3. **Tests for `places/parsing.py` and `places/factories.py`.** The new modules
   are exercised end-to-end through the client tests, but a small dedicated
   test file for `parse_new_place` (full New API payload shape) and the four
   factory functions (proper API key wiring + cache folder selection) would be
   a defensive improvement.
4. **Async batch enrichment.** `aenrich_saved_places` exists but its
   `rate_limit_delay` is a sync `time.sleep`. Switching to `asyncio.sleep`
   would let callers pipeline multiple enrichments without blocking the loop.
5. **Periodic Takeout sync.** Still an open product question (see
   [00-places-overview.md](./00-places-overview.md)); not relevant for Phase 1
   but should be answered before Phase 3 ingestion design.

## Next steps proposal

### Immediate (Phase 1 polish, optional)

1. Author `scratch_space/01_basic_usage.ipynb` covering the full
   parse -> enrich -> cluster pipeline against a real Takeout export.
2. Add `tests/places/conftest.py` with the shared HTTP mocking helpers; add
   focused tests for `places/parsing.py::parse_new_place` and
   `places/factories.py::make_*`.

### Phase 2 kickoff

3. Start
   [03-phase2-trip-me-up-rebuild.md](./03-phase2-trip-me-up-rebuild.md). First
   concrete commit: toolchain migration (uv, Python 3.14, ruff `select=ALL`),
   then replace `trip-me-up`'s `FindPlace`, `PlaceDetails`, and
   `req_get_cached` classes with imports from `places-tools`. Use
   `places.factories.make_find_place_client` / `make_place_details_client` so
   the API key + cache wiring lives in one place. Drop the duplicated code in
   `trip-me-up/src/`.
4. Wire `geo.distance_matrix.DistanceMatrixClient` into the trip planner; the
   public surface (`get_durations`, `get_distances`) was designed for this
   consumer.

### Phase 3 prerequisites

5. Before starting Phase 3, answer the remaining open questions in
   [00-places-overview.md](./00-places-overview.md): periodic Takeout sync
   strategy and the home of any vector-store / LLM integration. Confirmed
   decisions so far: Distance Matrix lives in `places-tools` (done in step
   1.6); vector store / LLM integration does **not** belong in
   `places-tools` and should land in the `saved-places` webapp on top of
   `llm-core`.

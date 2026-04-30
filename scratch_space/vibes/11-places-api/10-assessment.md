# Assess `places-tools` project

## Overview

plan made in this folder
`scratch_space/vibes/11-places-api/*`
were implemented in repo
`places-tools`

please analyze that repo and
- cross check that all the planned features were implemented, and if not, write a clear list of missing features and where they were planned to be implemented
- assess the overall code quality and propose meaningful improvements
- propose reasonable next steps for the project

## Implementation status

Phase 1 (`places-tools`) is mostly complete on paper but has a critical missing
module that breaks the verification suite. Phases 2 and 3 have not been
started (status tracker still says "not started", no work in `trip-me-up` or a
new `saved-places` repo).

### Phase 1 - sub-task by sub-task

| Sub-task | Plan ref | Status | Notes |
| -------- | -------- | ------ | ----- |
| 1.1 Repo bootstrap | [02-phase1 §1.1](./02-phase1-google-maps-tools.md) | done | Renamed to `places-tools`, uv + Python 3.14, deps in `pyproject.toml`. |
| 1.2 Data models | [§1.2](./02-phase1-google-maps-tools.md) | done | All seven models present in `src/places_tools/models/` (`SavedPlace`, `LatLng`, `AddressComponent`, `OpeningHours`, `Place`, `SavedList`, `Neighbourhood`). |
| 1.3 Takeout parser | [§1.3](./02-phase1-google-maps-tools.md) | done (gaps) | `csv_parser.py`, `geojson_parser.py`, `parse_takeout.py` with auto-detect. Missing: `saved_at` timestamp extraction, `place_id` resolution from Takeout URLs. No fixture-based tests for the parsers (`tests/takeout/` is missing entirely; only `tests/places/`, `tests/geo/`, etc. exist). |
| 1.4 HTTP caching layer | [§1.4](./02-phase1-google-maps-tools.md) | **missing** | `src/places_tools/cache/` does not exist. Only `config/cache_config.py` was created. `CacheStore[T]`, `PlaceCache`, `FindPlaceCache` were never implemented, despite being imported by `places/find_place_client.py`, `places/place_details_client.py`, `tests/places/test_places_clients.py`, and documented in `docs/library/cache.md`. This is the root cause of the suite failures below. |
| 1.5 Places API client | [§1.5](./02-phase1-google-maps-tools.md) | partial | `PlaceField` enum + `DEFAULT_FIELDS` (1.5a), `FindPlaceClient` with `PlaceNotFoundError` (1.5b), `PlaceDetailsClient` with `PlaceDetailsError` returning `Place` (1.5c), and `enrich_saved_places` (1.5e) all exist. Stretch goal 1.5d (Places API New) is **not implemented**: `api_version` exists as a config field but only the legacy endpoint is wired. |
| 1.6 Geo utilities | [§1.6](./02-phase1-google-maps-tools.md) | partial | `haversine`, `BoundingBox` + `filter_by_bbox`, `cluster_by_address`, `cluster_by_proximity` all present. Stretch 1.6d (Distance Matrix client) is **not implemented**. |
| 1.7 Params / config wiring | [§1.7](./02-phase1-google-maps-tools.md) | partial | `PlacesToolsParams`, `PlacesToolsPaths`, `PlacesApiParams`, `PlacesApiConfig` are wired and follow the standard pattern. **Missing:** `CacheConfig` is not aggregated into `PlacesToolsParams` (no `cache: CacheParams` attribute), so the configured `cache_fol` / `ttl_seconds` are never reachable from the singleton; the clients/tests construct caches with raw paths. |
| 1.8 Docs and verification | [§1.8](./02-phase1-google-maps-tools.md) | partial / failing | Docs exist (`docs/library/{cache,geo,models,places_api,takeout}.md`) but `cache.md` describes code that doesn't exist. The end-to-end notebook `scratch_space/01_basic_usage.ipynb` was **not created**; only the template scaffold notebook `scratch_space/02_places_tools_sample/01_params.ipynb` is present. Verification fails (see below). |

### Verification suite status

Run on the current repo:

- `uv run pytest`: collection error -
  `ModuleNotFoundError: No module named 'places_tools.cache'` from
  `tests/places/test_places_clients.py`. With that file ignored, **65 pass, 1 fail**:
  `tests/config/test_env_vars.py::test_env_vars` (`PLACES_TOOLS_SAMPLE_ENV_VAR` not set;
  template scaffold test that was never adapted).
- `uv run ruff check .`: 1 error (`I001` import ordering in
  `tests/places/test_places_clients.py`).
- `uv run pyright`: 4 errors, all
  `Import "places_tools.cache.place_caches" could not be resolved` in
  `find_place_client.py`, `place_details_client.py`, and the test file.

### Phase 2 / 3

Both phases are untouched. `trip-me-up` still uses Poetry / Python 3.11 and raw
JSON dicts; `saved-places` repo does not exist. None of the Phase 2 sub-tasks
(toolchain migration, dict-to-model replacement, distance matrix, itinerary
planner, CLI) or Phase 3 sub-tasks (FastAPI bootstrap, DB layer, ingestion,
browse UI, tagging, LLM features, deployment) have been started.

## Code quality assessment

Overall the code that does exist is small, readable, and follows the project
template conventions (loguru, Pydantic, custom exceptions, params/config
separation, Google-style docstrings). The main concerns are completeness and a
handful of robustness issues, not structural problems.

### Strengths

- One-class-per-file model layout in `models/`, clean `BaseModel` subclasses.
- `PlaceField` migrated cleanly from the boolean dataclass to a `StrEnum` as
  planned, with a frozen `DEFAULT_FIELDS` set.
- Clients are thin and easy to mock (`tests/places/test_places_clients.py` uses
  `unittest.mock.patch` on `httpx.get` directly).
- Custom exceptions (`PlaceNotFoundError`, `PlaceDetailsError`,
  `UnsupportedTakeoutFormatError`, `UnknownEnvLocationError`,
  `UnknownEnvStageError`) are used consistently instead of bare `ValueError`.
- Geo clustering is dependency-free (no sklearn) and matches the plan's
  "no ML dependency" constraint.
- CSV parser handles English and Italian headers with a single normalization map
  and `utf-8-sig` to strip BOMs.
- `params/places_api_params.py` masks `api_key` as `[REDACTED]` in `__str__`
  and uses `SecretStr` internally.

### Issues and improvements

**Critical**

1. **Cache module missing.** Implement `src/places_tools/cache/` with
   `cache_store.py` (generic `CacheStore[T]` with TTL, `get`/`set`/`invalidate`,
   filesystem-safe key sanitization) and `place_caches.py`
   (`FindPlaceCache(CacheStore[dict])` keyed by query, `PlaceCache(CacheStore[dict])`
   keyed by `place_id` + sorted field tuple). This unblocks tests, ruff, and
   pyright simultaneously.
2. **Wire `CacheConfig` into `PlacesToolsParams`.** Add a `CacheParams` class
   that loads `cache_fol` from `PlacesToolsPaths.cache_fol` and a default
   `ttl_seconds`, expose it as `params.cache`, and have the API clients accept
   a config-built cache rather than each caller constructing one.
3. **Adapt scaffold tests.** `tests/config/test_env_vars.py` still references
   the unrenamed `PLACES_TOOLS_SAMPLE_ENV_VAR`; either set it in `conftest.py`
   or update the assertion to a real env var the project actually uses
   (e.g. `GOOGLE_MAPS_API_KEY`, which `conftest.py` already injects).

**HTTP / client robustness**

4. `httpx.get` calls in `find_place_client.py` and `place_details_client.py`
   have no `timeout` and no retry/backoff. Add an explicit timeout (e.g. 10s)
   and a small retry policy for 5xx / network errors.
5. `FindPlaceClient.find` runs `quote(query)` then passes the already-encoded
   value through httpx's `params=`, which will percent-encode it again. Pass
   the raw query and let httpx handle encoding.
6. `enrich_saved_places` mutates the returned `Place` (`place.source_list = ...`,
   `place.user_note = ...`) after construction. Use `place.model_copy(update={...})`
   for clarity and to avoid surprising callers if `Place` ever becomes frozen.
7. The clients are sync-only. Given httpx's async support and the batch
   nature of `enrich_saved_places`, an async variant
   (`AsyncFindPlaceClient`, `AsyncPlaceDetailsClient`,
   `aenrich_saved_places`) would be a meaningful win for any consumer (Phase 2
   trip planner, Phase 3 webapp).

**Parsing**

8. `csv_parser` does not populate `place_id` even when the URL contains one
   (`https://maps.app.goo.gl/...` or `?q=place_id:...`). Adding a small URL
   parser would let downstream code skip the Find Place round-trip.
9. Neither parser populates `saved_at`, although the field is on `SavedPlace`
   and the plan explicitly lists "timestamps" as a Takeout-derived field.
10. No tests under `tests/takeout/`. Add fixture-based tests covering CSV
    English/Italian headers, missing optional columns, empty file, and a
    minimal GeoJSON FeatureCollection.

**API surface / docs**

11. `docs/library/cache.md` is aspirational and currently misleads readers;
    keep it but only after the module exists.
12. No `scratch_space/01_basic_usage.ipynb` end-to-end notebook (planned in
    1.8). This is the smallest possible integration test of the full pipeline
    (parse -> enrich -> cluster) and would have caught the cache import error
    immediately.
13. `PlaceField` includes both legacy and new fields but only the legacy
    endpoint is used. Either commit to legacy and remove the
    `api_version: Literal["legacy", "new"]` flag, or implement the New API
    path properly.

**Minor**

14. `cluster_by_proximity` builds `Neighbourhood` objects but never sets
    `name`; consider deriving a default name (e.g. dominant locality of
    members) to make the result usable downstream.
15. `_FakeResponse` in tests is duplicated logic; pulling it into a shared
    fixture in `tests/places/conftest.py` would simplify future client tests.
16. `enrich_saved_places` swallows all `PlaceDetailsError`s with a warning;
    consider returning a structured result (`(enriched, failed)`) so callers
    can surface failures.

## Next steps proposal

Recommended order, based on impact and unblocking effect.

### Immediate (unblock the suite)

1. Implement `places_tools.cache.cache_store.CacheStore[T]` and
   `places_tools.cache.place_caches.{FindPlaceCache, PlaceCache}` to match the
   shapes already imported by the clients, tests, and docs.
2. Fix `tests/config/test_env_vars.py` and the ruff import-order error.
3. Confirm `uv run pytest && uv run ruff check . && uv run pyright` is green
   and add a `Makefile` / pre-commit step so this can't drift again.

### Short term (round out Phase 1)

4. Wire `CacheConfig` / `CacheParams` into `PlacesToolsParams` and expose a
   factory that builds API clients from the singleton (`make_find_client()`,
   `make_details_client()`).
5. Add HTTP timeouts + a thin retry layer (e.g. `httpx.Client(transport=
   httpx.HTTPTransport(retries=3))`) and unit tests for the retry path.
6. Write `scratch_space/01_basic_usage.ipynb` covering: parse CSV / GeoJSON
   ->`enrich_saved_places` -> `cluster_by_address` /
   `cluster_by_proximity` -> render with rich.
7. Add `tests/takeout/` fixtures + tests.

### Medium term (decide on stretch goals)

8. Either implement Places API (New) behind the existing `api_version` flag
   (field masks, single endpoint, `X-Goog-FieldMask` header) or remove the
   flag.
9. Add an optional `geo/distance_matrix.py` module (`DistanceMatrixClient`)
   - this is a Phase 2 prerequisite and belongs in `places-tools` per the
   open question in [00-places-overview.md](./00-places-overview.md).
10. Add an async variant of the API clients and `enrich_saved_places` to make
    the library cleanly usable from FastAPI (Phase 3).

### Phase 2 kickoff

11. Start [03-phase2-trip-me-up-rebuild.md](./03-phase2-trip-me-up-rebuild.md)
    only after steps 1-7 are done. The first concrete commit there should be
    the toolchain migration (uv, Python 3.14, ruff ALL), then replace the
    `FindPlace` / `PlaceDetails` / `req_get_cached` classes with the
    `places-tools` equivalents and delete the duplicated code in
    `trip-me-up/src/`.

### Phase 3 prerequisites

12. Before starting Phase 3, decide the open questions in
    [00-places-overview.md](./00-places-overview.md): Distance Matrix scope
    (likely yes, after step 9), periodic Takeout sync vs. one-time import,
    and where the vector-store / LLM integration belongs (recommend keeping
    it in the `saved-places` webapp on top of `llm-core`, not in
    `places-tools`).

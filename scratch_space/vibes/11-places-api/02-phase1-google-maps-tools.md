# Phase 1 - Create `google-maps-tools` library

**Status:** not started  
**Depends on:** nothing (greenfield)  
**Blocks:** Phase 2 (trip-me-up rebuild), Phase 3 (saved-places)

Extract and modernize the Google Maps / Places logic from `trip-me-up` into a
standalone, installable library following the standard project template
conventions (uv, ruff ALL, pyright, Python 3.14).

---

## 1.1 - Repo bootstrap

**Status:** not started

- Create `google-maps-tools` from `python-project-template` via `rename-project`.
- Configure `pyproject.toml`: package name `google_maps_tools`, Python >= 3.14.
- Add initial dependencies: `pydantic`, `httpx` (async-capable HTTP), `loguru`.
- Set up `~/cred/google-maps-tools/.env` placeholder with `GOOGLE_MAPS_API_KEY`.
- Verify: `uv run pytest && uv run ruff check . && uv run pyright` all pass on empty scaffold.

---

## 1.2 - Canonical place data models

**Status:** not started

Define the core Pydantic models that every sub-project will share. These live in
`src/google_maps_tools/models/`.

Models to create:

| Model | Key fields |
| ----------- | ------------------------------------------------------------------ |
| `SavedPlace` | `place_id?`, `name`, `url`, `note`, `list_name`, `saved_at` |
| `LatLng` | `lat: float`, `lng: float` |
| `AddressComponent` | `long_name`, `short_name`, `types: list[str]` |
| `OpeningHours` | `open_now: bool?`, `periods`, `weekday_text: list[str]` |
| `Place` | full enriched place; see below |
| `SavedList` | `name`, `places: list[SavedPlace]` |
| `Neighbourhood` | `name`, `center: LatLng`, `members: list[Place]` |

`Place` fields: `place_id`, `name`, `formatted_address`,
`address_components: list[AddressComponent]`, `location: LatLng`,
`types: list[str]`, `rating: float?`, `user_ratings_total: int?`,
`price_level: int?`, `editorial_summary: str?`, `website: str?`,
`phone: str?`, `opening_hours: OpeningHours?`, `photos: list[str]` (photo
references), `source_list: str?`, `user_note: str?`, `visited: bool`.

Design rules:
- All models extend `BaseModel` (no kwargs forwarding needed here).
- Every optional field uses `field = None` default.
- No env-var reads inside models.

---

## 1.3 - Google Takeout parser

**Status:** not started

Module: `src/google_maps_tools/takeout/`

Parse Google Takeout exports into typed `SavedPlace` / `SavedList` models.

Sub-tasks:

**1.3a - CSV parser**
- Input: path to a Google Takeout CSV file (can have `Titolo` / `Title`, `Note`,
  `URL`, `Comment` columns; header row may be in Italian or English).
- Output: `SavedList` with a `list[SavedPlace]`.
- Handle missing optional columns gracefully.
- Replaces the ad-hoc CSV read in `trip-me-up/scratch_space/`.

**1.3b - GeoJSON parser**
- Input: path to a `Saved Places.json` GeoJSON file from Takeout.
- Output: `SavedList`; populate `LatLng` directly from GeoJSON coordinates
  instead of requiring a Find Place lookup later.
- Extract `name`, `google_maps_url`, and feature properties.

**1.3c - Auto-detect format**
- `parse_takeout(path: Path) -> SavedList` dispatches to CSV or GeoJSON based
  on file extension / sniffed content.

Tests: unit tests with fixture files covering both formats, missing columns,
empty files, and mixed encodings.

---

## 1.4 - HTTP caching layer

**Status:** not started

Module: `src/google_maps_tools/cache/`

Replace the simple `req_get_cached` from `trip-me-up` with a proper cache.

Requirements:
- Cache key based on semantic identity (e.g. `place_id` + sorted field set),
  NOT raw URL hash.
- Optional TTL: cache entries older than N seconds are considered stale and
  re-fetched.
- Storage backend: JSON files under a configurable folder (same approach as
  existing code, but structured).
- `CacheStore[T]` generic class: `get(key) -> T | None`, `set(key, value)`,
  `invalidate(key)`.
- Separate `PlaceCache` and `FindPlaceCache` thin wrappers with typed return
  types.
- `CacheConfig(BaseModelKwargs)` with `cache_fol: Path` and
  `ttl_seconds: int | None = None`.

---

## 1.5 - Google Places API client

**Status:** not started

Module: `src/google_maps_tools/places/`

Port and modernize `FindPlace` and `PlaceDetails` from `trip-me-up`.

**1.5a - Field selection**
- Replace the boolean-flag `PlaceDetailsFields` dataclass with a
  `PlaceField(str, Enum)` enum whose values are the exact API field strings.
- `DEFAULT_FIELDS: frozenset[PlaceField]` covers the fields needed for the
  canonical `Place` model.

**1.5b - Find Place client**
- `FindPlaceClient.find(query: str) -> str | None` returns a `place_id` or
  `None` for zero results.
- Uses `CacheStore` for caching.
- Raises `PlaceNotFoundError` (custom exception, not bare `ValueError`) when
  status is not `OK` or `ZERO_RESULTS`.

**1.5c - Place Details client**
- `PlaceDetailsClient.get(place_id: str, fields: set[PlaceField] = DEFAULT_FIELDS) -> Place`
- Deserializes the raw response into the canonical `Place` model.
- Uses `CacheStore` with TTL.
- Raises `PlaceDetailsError` for API errors.

**1.5d - Places API (New) support** _(stretch goal)_
- Both API versions behind an `api_version: Literal["legacy", "new"] = "legacy"`
  config flag.
- New API uses field masks and a single endpoint.

**1.5e - Batch enrichment helper**
- `enrich_saved_places(places: list[SavedPlace], ...) -> list[Place]`
- Optionally run Find Place for entries without a `place_id`, then fetch
  details for all.
- Respects a configurable rate-limit delay between requests.

---

## 1.6 - Geo utilities

**Status:** not started

Module: `src/google_maps_tools/geo/`

**1.6a - Haversine distance**
- `haversine(a: LatLng, b: LatLng) -> float` returns distance in kilometres.
- Pure function, no network calls.

**1.6b - Bounding-box filter**
- `filter_by_bbox(places: list[Place], bbox: BoundingBox) -> list[Place]`.
- `BoundingBox(sw: LatLng, ne: LatLng)` Pydantic model.

**1.6c - Neighbourhood clustering**
- `cluster_by_address(places: list[Place], level: str = "locality") -> dict[str, list[Place]]`
  groups places by the value of a given `address_components` type.
- `cluster_by_proximity(places: list[Place], radius_km: float) -> list[Neighbourhood]`
  simple threshold-based clustering (no ML dependency).

**1.6d - Distance Matrix integration** _(stretch goal)_
- `DistanceMatrixClient.get_durations(origins, destinations, mode) -> list[list[int]]`
  wraps the Google Distance Matrix API and returns seconds.

---

## 1.7 - Params / config wiring

**Status:** not started

- `GoogleMapsToolsParams` singleton following the standard pattern.
- `GoogleMapsToolsPaths` with `cache_fol`, `data_fol`.
- `PlacesApiConfig(BaseModelKwargs)` with `api_key: SecretStr`,
  `api_version`, `rate_limit_delay: float = 0.1`.
- `PlacesApiParams` loads `GOOGLE_MAPS_API_KEY` from env.
- `CacheConfig` wired through params.

---

## 1.8 - Docs and verification

**Status:** not started

- Write `docs/library/places_client.md` and `docs/library/takeout_parser.md`.
- Full verification: `uv run pytest && uv run ruff check . && uv run pyright`.
- Add a scratch-space notebook `scratch_space/01_basic_usage.ipynb` showing
  end-to-end: parse CSV -> enrich places -> access `Place` fields.

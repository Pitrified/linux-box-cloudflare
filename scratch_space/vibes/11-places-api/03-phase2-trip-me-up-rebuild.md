# Phase 2 - Rebuild `trip-me-up` on `google-maps-tools`

**Status:** not started  
**Depends on:** Phase 1 (google-maps-tools >= 1.5, 1.6 complete)  
**Blocks:** nothing (standalone improvement)

Modernize the existing `trip-me-up` repo: replace ad-hoc API calls and raw
dicts with `google-maps-tools` models, implement the itinerary planning that was
originally scoped but never built, and migrate the toolchain to match current
project-template conventions.

---

## 2.1 - Toolchain migration

**Status:** not started

Migrate from Poetry + Python 3.11 to uv + Python 3.14 and adopt
project-template conventions.

Sub-tasks:

**2.1a - uv migration**
- Delete `pyproject.toml` (Poetry format) and `poetry.lock`.
- Re-initialise with `uv init --python 3.14`.
- Re-add dependencies: `google-maps-tools` (local path dep), `langchain`,
  `chromadb`, `loguru`, `pydantic`, `jupyter`.
- Verify `uv run pytest` passes.

**2.1b - Ruff + pyright setup**
- Copy `ruff.toml` from project template.
- Add `pyproject.toml` pyright settings section (srcPaths = `["src"]`).
- Fix all lint and type errors surfaced on the existing code before further
  changes.

**2.1c - Project structure alignment**
- Move source to `src/trip_me_up/`.
- Create `src/trip_me_up/params/` following the params/config pattern.
- Move notebooks to `scratch_space/`; name `01_*`, `02_*`, etc.
- Update imports throughout.

---

## 2.2 - Replace raw API calls and dict-passing

**Status:** not started  
**Depends on:** 2.1, Phase 1 done (1.3, 1.4, 1.5)

Swap out the legacy `FindPlace` / `PlaceDetails` / `req_get_cached` code for
`google-maps-tools` equivalents.

Sub-tasks:

**2.2a - Takeout ingestion**
- Replace the ad-hoc CSV read (`pd.read_csv(…)["Titolo"]`) with
  `google_maps_tools.takeout.parse_takeout(path) -> SavedList`.
- Output is now a typed `SavedList` instead of a plain list of strings.

**2.2b - Place enrichment**
- Replace manual `FindPlace(...).find_place()` + `PlaceDetails(...).get()`
  chains with `google_maps_tools.places.enrich_saved_places(saved_list.places)`.
- All downstream code works with `Place` objects instead of raw dicts.

**2.2c - Remove legacy modules**
- Delete the old `src/trip_me_up/find_place.py`, `place_details.py`,
  `cached_request.py` (or equivalent notebook-level code) once the replacement
  is confirmed working.

**2.2d - Update scratch notebooks**
- Rewrite `scratch_space/01_ingest.ipynb` using the new imports.
- Ensure all notebooks run end-to-end without errors.

---

## 2.3 - Distance matrix and neighbourhood layout

**Status:** not started  
**Depends on:** 2.2, Phase 1 done (1.6)

Implement the distance / neighbourhood features that were scoped in the original
roadmap but never built.

Sub-tasks:

**2.3a - Neighbourhood grouping**
- `TripPlanner.group_by_neighbourhood(places: list[Place]) -> list[Neighbourhood]`
  using `google_maps_tools.geo.cluster_by_address`.
- Display summary: neighbourhood name, place count, bounding box.

**2.3b - Intra-neighbourhood distances**
- For each neighbourhood, compute the haversine distance matrix between all
  constituent places.
- Store as a `DistanceMatrix` model (list of `(place_a, place_b, km)` triples).

**2.3c - Inter-neighbourhood walking times** _(stretch; requires Phase 1 1.6d)_
- Use `DistanceMatrixClient` to fetch actual walking/transit times between
  neighbourhood centroids.
- Cache results to avoid repeated API calls.

---

## 2.4 - Itinerary planner

**Status:** not started  
**Depends on:** 2.3

Build a basic itinerary generator that assigns places to days.

Sub-tasks:

**2.4a - Day-allocation heuristic**
- `ItineraryPlanner.plan(places, days: int) -> Itinerary`
- Groups places into `days` buckets trying to minimize intra-day travel
  (greedy nearest-neighbour starting from the convex hull).
- `Itinerary` model: `days: list[ItineraryDay]`;
  `ItineraryDay`: `date: date?`, `places: list[Place]`, `total_distance_km: float`.

**2.4b - Constraint support**
- Respect opening hours: flag places whose `opening_hours` conflicts with the
  assigned day.
- Input: optional `must_visit: set[place_id]` and
  `avoid_dates: list[date]` constraints.

**2.4c - Rendering**
- `render_itinerary(itinerary: Itinerary) -> str` produces a human-readable
  markdown summary.
- Scratch notebook `scratch_space/03_itinerary.ipynb` demonstrates usage.

---

## 2.5 - Optional CLI

**Status:** not started  
**Depends on:** 2.2, 2.3, 2.4

Expose key flows as a Typer CLI so the app is usable outside notebooks.

Commands:

| Command | Description |
| ----------------------- | -------------------------------------------- |
| `trip ingest <csv>` | Parse Takeout export, enrich, save to cache |
| `trip neighbourhoods` | Print neighbourhood grouping |
| `trip plan --days N` | Generate and print itinerary |

---

## 2.6 - Verification

**Status:** not started

- `uv run pytest` (unit tests for planner logic with mock place data).
- `uv run ruff check . && uv run pyright`.
- Smoke-run the two primary scratch notebooks end-to-end.

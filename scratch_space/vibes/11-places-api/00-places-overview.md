# Overview of the place-based projects

## Current repos

We have one existing and two planned projects in the place/maps space.

**`trip-me-up`** - Trip planner from Google Maps saved lists. Takes a Google
Takeout export, fetches place details, computes distances between neighbourhoods,
and plans an itinerary.

**`saved-places`** _(planned)_ - Webapp to view and manage Google Maps saved places. Syncs with Google Takeout exports, provides a nicer UI for browsing and organizing saved places.

**`google-maps-tools`** _(planned)_ - Installable library for working with Google Maps data. Provides utilities for parsing Takeout exports, fetching place details, and computing distances.

## Overview

we want to analyze the repo in terms of:

- Functionality: what does the app do, what features does it have, what user needs does it address?
- Internal data models for place-related concepts: what are the main data structures and models used in the app, how do they relate to the functionality? eg places, neighborhoods, itineraries, etc. Data models for users and authentication are out of scope for this analysis, we want to focus on the place-related data models.

## Functional analysis

### `trip-me-up` (existing)

A notebook-driven trip planner that starts from a Google Maps saved-places list
and enriches each entry with Google Places API data. The repo is exploratory
(no webapp, no CLI) - all usage flows through Jupyter notebooks in
`scratch_space/`.

**Ingestion**

- Reads a CSV file exported from Google Takeout (the "Saved" / "Da visitare"
  list). The CSV has a `Titolo` (title) column with human-readable place names.
- No parser for GeoJSON or other Takeout formats; only CSV is supported.

**Place resolution (Find Place API)**

- `FindPlace` takes a free-text place description and calls the Google Places
  _Find Place from Text_ endpoint to obtain a `place_id`.
- Results are validated (`OK` / `ZERO_RESULTS`) and cached to disk as JSON.

**Place enrichment (Place Details API)**

- `PlaceDetails` fetches a rich set of fields for a given `place_id`:
  address components, opening hours, editorial summary, geometry (lat/lng),
  rating, price level, phone, website, types.
- Which fields to request is controlled by a `PlaceDetailsFields` dataclass
  with boolean flags; the class serializes active flags into the API query
  string.
- Responses are cached (same caching layer as Find Place).

**Caching layer**

- `req_get_cached` is a generic HTTP-GET-to-JSON cacher. It hashes the full
  URL (via SHA-256 `Hasher`) to generate a cache filename, stores the response
  under a configurable folder, and returns the cached version on subsequent
  calls.
- An optional `validator` callback lets the caller decide whether a response
  is worth caching (e.g. skip caching error responses).

**Vector store (partial)**

- `VectorDB` extends LangChain's `Chroma` to deduplicate documents by
  content-hash before insertion.
- There is no code that actually populates the vector store with place data
  or queries it for trip planning; this looks like groundwork for a future
  "chat with your trip" feature that was never completed.

**Hashing utility**

- `Hasher` wraps `hashlib.sha256` with a fluent API. Used for both cache
  key generation and vector-store document IDs.

**What is missing / not implemented**

- No data models (Pydantic or otherwise) for Place, Neighbourhood, Itinerary,
  or Trip. Place data lives as raw JSON dicts throughout.
- No distance computation between places or neighbourhoods.
- No itinerary planning or optimization.
- No user interaction / chat layer (the vector-store stub hints at it, but
  nothing is wired up).
- No CLI or webapp; pure notebook exploration.
- Uses Poetry + Python 3.11; does not follow the newer uv-based project
  template conventions.

### `saved-places` (planned)

Not yet created. Intended as a webapp for browsing and organizing Google Maps
saved places. No code to analyze.

### `google-maps-tools` (planned)

Not yet created. Intended as a shared library for Google Maps data operations.
No code to analyze.

## Common components

Looking across the existing `trip-me-up` code and the planned repos, several
functional areas emerge as shared concerns.

### 1. Google Takeout parsing

`trip-me-up` only reads a single CSV column (`Titolo`). Google Takeout exports
for saved places include richer data (coordinates, notes, list membership,
timestamps) and can come in both CSV and GeoJSON formats. A shared parser
should handle all of these.

### 2. Google Places API client

The `FindPlace` and `PlaceDetails` classes in `trip-me-up` are functional but
tightly coupled to raw JSON responses and hand-built URL templates. A shared
client should:

- Use the newer Places API (New) where possible (field masks, single endpoint).
- Return typed Pydantic models instead of raw dicts.
- Support batch operations natively.
- Handle rate limiting and retries.

### 3. Caching / HTTP layer

`req_get_cached` is useful but minimal. A shared caching layer should:

- Support TTL-based expiration (place details can go stale).
- Key on semantic identity (place_id + requested fields) rather than raw URL.
- Be decoupled from the hashing utility.

### 4. Place data model

`trip-me-up` has no structured place model; everything is a raw dict. All three
projects need a canonical `Place` model that holds at minimum:

- Identity: `place_id`, `name`, source list (which saved list it came from).
- Location: `lat`, `lng`, `formatted_address`, `address_components`, neighbourhood/area.
- Metadata: `types`, `rating`, `price_level`, `editorial_summary`, `website`, `phone`.
- Opening hours (structured).
- User-level data: tags, notes, visit status.

### 5. Distance / geo utilities

`trip-me-up` mentions distance computation but never implements it. A shared
utility should provide haversine distance, neighbourhood clustering, and
optionally Google Distance Matrix integration for walking / transit times.

### 6. Vector store / LLM integration

The `VectorDB` wrapper for deduplication is generic and could live in a shared
library (or lean on `llm-core`'s existing `CChroma` / `EntityStore`).

## Roadmap

A phased approach to unifying the three projects around a shared foundation.

### Phase 1 - Extract `google-maps-tools` from `trip-me-up`

1. Create the `google-maps-tools` repo from the project template (uv, ruff,
   pyright, Python 3.14).
2. Port and modernize the Google Places API client:
   - `FindPlace` and `PlaceDetails`, returning Pydantic models.
   - Configurable field selection via a typed enum/set instead of a boolean
     dataclass.
   - Support for the Places API (New) alongside the legacy endpoint.
3. Port and generalize the caching layer (TTL, semantic keys).
4. Add a Takeout parser that handles both CSV and GeoJSON exports, returning
   typed `SavedPlace` models with list membership and timestamps.
5. Add geo utilities: haversine distance, bounding-box filtering,
   neighbourhood clustering (by address component or lat/lng proximity).
6. Define the canonical `Place` Pydantic model and any related models
   (`Neighbourhood`, `SavedList`).

### Phase 2 - Rebuild `trip-me-up` on top of `google-maps-tools`

1. Replace the raw API calls and dict-passing with `google-maps-tools` models
   and client.
2. Implement the distance matrix and itinerary planner that was originally
   scoped but never built.
3. Migrate from Poetry to uv; bump to Python 3.14; adopt the project template
   conventions (params/config pattern, loguru, ruff ALL).
4. Optionally add a simple CLI or webapp for non-notebook usage.

### Phase 3 - Build `saved-places` webapp

1. Create the repo from the project template (FastAPI + HTMX from
   `fastapi-tools`).
2. Import places via `google-maps-tools` Takeout parser.
3. Store enriched places in a local DB (SQLAlchemy, same pattern as `kit-hub`).
4. Build browse/search/filter UI: by list, neighbourhood, type, rating.
5. Add tagging, notes, and visit-status tracking.
6. Optionally integrate LLM features (natural-language search via vector
   store) using `llm-core`.

### Open questions

- Should `google-maps-tools` also wrap the Distance Matrix and Directions
  APIs, or keep scope limited to Places + Takeout?
  ANSWER: yes, we implemented a generic `places-tools`. a dedicated module for distance can be added.
- Should `saved-places` sync periodically with Google Takeout, or is a
  one-time import sufficient?
  ANSWER: manual import is fine for now; we can add periodic sync later if needed.
- How much of the vector-store / LLM integration belongs in
  `google-maps-tools` vs. in the consuming apps?
  ANSWER: none. places api do something else, consumer app will decide if and how to use it.

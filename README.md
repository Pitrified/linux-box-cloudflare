# One box to rule them all

## Infrastructure

**`linux-box-cloudflare`** - Cloudflare Tunnel setup and docs. Entry point for
all internet-exposed services. Registers subdomains and routes per app.

Head over to [01_box_setup.md](docs/01_box_setup.md) for detailed instructions on setting up your Linux box and exposing it via Cloudflare Tunnel.

**`dotfiles`** - Personal dotfiles. Includes shell config, editor config, and other
personalization. Managed with custom python script.

---

## Framework / Tooling

**`python-project-template`** - Copier template for bootstrapping new Python
projects. Provides: uv, ruff, pyright, pre-commit, pytest, mkdocs/GitHub Pages,
src layout, env loading, path management, and a FastAPI webapp scaffold (the
scaffold portion is being extracted into `fastapi-tools`).

**`fastapi-tools`** _(new)_ - Installable library extracted from the template.
Provides: `create_app()` factory, Google OAuth, session management, security
middleware (CSP, trusted hosts, proxy headers), Jinja2 templating, health
router, common schemas and exceptions. All FastAPI micro-services depend on this.

**`llm-tools`** _(planned)_ - Installable library for LLM-driven projects. Provides: prompt
templates, structured output parsing with Pydantic, and common LLM chains. Used by
`convo-craft` and `laife` for prompt management and response parsing.

**`python-tools`** _(planned)_ - Installable library for general Python utilities.
Provides: config management with Pydantic, standardized logging, and helper
functions and classes (eg. `Singleton`, `BaseModelKwargs`). Used across all
projects for config and logging consistency.

---

## Interfaces / Bots

**`tg-central-hub-bot`** - Telegram bot + companion FastAPI webapp. Primary
low-friction user interface for the linux-box ecosystem. Webapp includes Google
OAuth, an internal backend app (127.0.0.1 only) secured with a bot API key, and
correct OAuth callback handling behind Cloudflare Tunnel.

---

## Recipe Domain

**`recipamatic`** - Recipe ingestion pipeline. Scrapes Instagram reels,
downloads media, extracts metadata and captions, stores raw/vague recipes.
Python backend + Svelte frontend.

**`recipinator`** - Recipe CRUD service. Normalized data model (Recipe →
Preparation → Step → Ingredient, Tags, Authors). FastAPI backend + React
frontend. Target canonical recipe service.

**`cookbook`** - Personal static recipe site in Italian. Jekyll + GitHub Pages.
Live at `pitrified.github.io/cookbook`.

**`recipe-model`** _(planned)_ - Recipe data model and validation library.
Pydantic models for recipes, ingredients, and related entities.
Exposes a vector embedding function for recipe search,
and a configurable parser for extracting structured recipes from unstructured text.

---

## Language Learning

**`convo-craft`** - Generates bilingual conversations via LLM, lets the user
translate one side to practice a target language. Streamlit UI, LangChain /
OpenAI backend, structured output with Pydantic.

**`brazilian-bites`** - Flashcard minimal app. Heavy focus on false friends.
React + shadcn/ui + Tailwind + Supabase. Built with Lovable.

---

## Travel / Maps

**`trip-me-up`** - Trip planner from Google Maps saved lists. Takes a Google
Takeout export, fetches place details, computes distances between neighbourhoods,
and plans an itinerary.

---

## AI / Simulation

**`laife`** - LLM-driven life simulation game. Players with missions, a world
engine, buildings, utensils, terrain. Brain → Action → World request loop.
Pygame renderer. LangChain + OpenAI. Most complex project in the ecosystem.

---

## Computer Vision

**`climbing-wire`** - Pose tracking on climbing videos. MediaPipe landmarks +
OpenCV homographies to warp and overlay joint traces across frames. DTW for
video alignment.

**`holo-table`** - Air pinch-to-zoom gesture via MediaPipe hand tracking.
Client sends gesture data to a server which drives a remote display. Designed
for touchless fractal zoom demos.

**`abyss`** - 3D viewer geometry: given a viewer position and a screen position,
compute and render what the viewer sees on the screen.

**`pose-tools`** _(planned)_ - Installable library for pose tracking and analysis. Provides
common utilities for working with pose data, including MediaPipe integration, homography utilities.

---

## Planned

**`social-media-downloader`** _(planned)_ - Micro-service to download media and
extract metadata from social URLs (Instagram, YouTube, WebPages etc.). Clean boundary:
input is a URL, output is a structured `DownloadedMedia` object. Used by
`recipamatic` and `tg-central-hub-bot`.

**`pitrified.github.io`** _(planned)_ - Personal static site. zensical + GitHub Pages. Home for
the blog and other static content, presenting this framework.

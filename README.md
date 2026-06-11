# One box to rule them all

## Overview

Visit
[https://Pitrified.github.io/linux-box-cloudflare/](https://Pitrified.github.io/linux-box-cloudflare/)
for a visual overview of the Linux box ecosystem.

## AI / Simulation

**`laife`** - LLM-driven life simulation game. Players with missions, a world
engine, buildings, utensils, terrain. Brain → Action → World request loop.
Pygame renderer. LangChain + OpenAI. Most complex project in the ecosystem.

---

## Recipe Domain

**`kit-hub`** - Folded in `recipe-model`, but still has to expose the actual
vector embedding search function. Does the recipe writing part, with an input
UI and classic search functionality.

**`recipe-model`** _(folded into `kit-hub`)_ - Recipe data model and validation library.
Pydantic models for recipes, ingredients, and related entities.
Still have to decide if this should be standalone and if i want a central recipe database.

**`recipamatic`** _(legacy)_ - Recipe ingestion pipeline. Scrapes Instagram reels,
downloads media, extracts metadata and captions, stores raw/vague recipes.
Python backend + Svelte frontend.

**`recipinator`** _(legacy)_ - Recipe CRUD service. Normalized data model (Recipe →
Preparation → Step → Ingredient, Tags, Authors). FastAPI backend + React
frontend. Target canonical recipe service.

**`cookbook`** - Personal static recipe site in Italian. Jekyll + GitHub Pages.
Live at [pitrified.github.io/cookbook](https://pitrified.github.io/cookbook).

---

## Language Learning

**`lang-tools`** - Folded all 5 of the next projects into this (too much).
Should be more focused on providing high-quality words and data for language learning, and some core functionality for word ingestion and management. Will leverage Git Large File Storage for storing word lists and data.

**`lang-tutor`** _(planned)_ - where we split the exercise functionality from lang tools, which is doing too many things. lang tutor is the llm based exercise generator and manager, with ui and everything.

**`convo_craft`** _(folded)_ - Generates bilingual conversations via LLM, lets the user translate one side to practice a target language.
Streamlit UI, LangChain / OpenAI backend, structured output with Pydantic.
A conversation is created, each sentence split in pieces and shuffled, the user has to reorder them.

**`brazilian-bites`** _(folded)_ - Flashcard minimal app. Heavy focus on false friends.
React + shadcn/ui + Tailwind + Supabase. Built with Lovable.
Note that there are some large `.csv` files (not tracked), which are semi-ready to be ingested (there is some upload endpoint to do so).

**`accenter`** _(folded)_ - write words with diacritics to practice accent placement in Portuguese.
It's a refactor of `go-accenter` which did the same in `go` for french.

**`worlde-multilingual`** _(folded)_ - Multilingual Wordle clone, with different languages and word lengths.
It's a refactor of `worldly-words` which was done with lovable.

**`fala-comigo-ai-tutor`** _(folded)_ was a lovable experiment of the tutor,
generating the conversation with corrections and feedback.

---

## Travel / Maps

**`trip-me-up`** - Trip planner from Google Maps saved lists. Takes a Google
Takeout export, fetches place details, computes distances between neighbourhoods,
and plans an itinerary.
almost all was folded into places-tools, this will be updated to provide the actual trip planning functionality

**`saved-places`** _(planned)_ - Webapp to view and manage Google Maps saved places. Syncs with Google Takeout exports, provides a nicer UI for browsing and organizing saved places.

**`google-maps-tools`** _(done as places-tools)_ - Installable library for working with Google Maps data.
Provides utilities for parsing Takeout exports, fetching place details, and computing distances.

---

## Extended Reality

**`climbing-wire`** - Pose tracking on climbing videos. MediaPipe landmarks +
OpenCV homographies to warp and overlay joint traces across frames. DTW for
video alignment.

**`holo-table`** - Air pinch-to-zoom gesture via MediaPipe hand tracking.
Client sends gesture data to a server which drives a remote display. Designed
for touchless fractal zoom demos.

**`abyss`** - 3D viewer geometry: given a viewer position and a screen position,
compute and render what the viewer sees on the screen.

**`pose-tools`** _(done)_ - Installable library for pose tracking and analysis. Provides
common utilities for working with pose data, including MediaPipe integration, homography utilities.

---

## Epub handling

**`interleaver?`** - Tool to interleave two epub files paragraph by paragraph. Useful for language learning with bilingual ebooks.

**`???`** - things i'm forgetting

---

## Framework / Tooling

**`python-project-template`** - Copier template for bootstrapping new Python
projects. Provides: uv, ruff, pyright, pre-commit, pytest, mkdocs/GitHub Pages,
src layout, env loading, path management.

**`fastapi-tools`** - Installable library extracted from the template.
Provides: `create_app()` factory, Google OAuth, session management, security
middleware (CSP, trusted hosts, proxy headers), Jinja2 templating, health
router, common schemas and exceptions. All FastAPI micro-services depend on this.

**`llm-core`** - Installable library for LLM-driven projects. Provides: prompt
templates, structured output parsing with Pydantic, and common LLM chains. Used by
`convo-craft` and `laife` for prompt management and response parsing.
Also includes voice transcription and generation utilities, it's planned to include
other media generation utilities in the future (eg. image generation).

**`python-tools`** _(scaffolded)_ - Installable library for general Python utilities.
Provides: config management with Pydantic, standardized logging, and helper
functions and classes (eg. `Singleton`, `BaseModelKwargs`). Used across all
projects for config and logging consistency.

**`social-media-downloader`** _(done as media-downloader)_ - Micro-service to download media and
extract metadata from social URLs (Instagram, YouTube, WebPages etc.). Clean boundary:
input is a URL, output is a structured `DownloadedMedia` object.

---

## Interfaces / Bots

**`tg-central-hub-bot`** - Telegram bot + companion FastAPI webapp. Primary
low-friction user interface for the linux-box ecosystem. Webapp includes Google
OAuth, an internal backend app (127.0.0.1 only) secured with a bot API key, and
correct OAuth callback handling behind Cloudflare Tunnel.

---

## Infrastructure

**`linux-box-cloudflare`** - Cloudflare Tunnel setup and docs. Entry point for
all internet-exposed services. Registers subdomains and routes per app. Head over to [01_box_setup.md](docs/01_box_setup.md) for detailed instructions on setting up your Linux box and exposing it via Cloudflare Tunnel.

**`dotfiles`** - Personal dotfiles. Includes shell config, editor config, and other
personalization. Managed with custom python script.

**`pitrified.github.io`** _(planned)_ - Personal static site. zensical + GitHub Pages.
Home for the blog and other static content. A more traditional static site for blogging and documentation and portfolio and whatnot.

**`repomgr`** - Repository management tool. Helps with organizing and maintaining multiple repositories.

---

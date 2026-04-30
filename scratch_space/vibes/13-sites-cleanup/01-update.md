# Site overview updateo

## Context

in `sites/overview/index.html`
there are just the initial bubbles with placeholder content.

gather context from README.md, repos in the workspaces, `configs/repomgr/repos.toml` to understand what the main projects are and how they are grouped

keep high level projects at the top, and more specific sub-projects or common tools as we go down in the page
include a bubble for the "Linux box ecosystem" as a whole

## Plan

**Groups (top to bottom), 23 bubbles total:**

| Row | Group | Projects | Color |
|-----|-------|----------|-------|
| 1 | Ecosystem (1) | `linux-box-cloudflare` | green |
| 2 | Flagship apps (3) | `laife`, `kit-hub`, `tg-central-hub-bot` | teal |
| 3 | Core libraries (5) | `llm-core`, `fastapi-tools`, `media-downloader`, `python-project-template`, `repomgr` | violet |
| 4 | Recipe domain (3) | `recipamatic`, `recipinator`, `cookbook` | orange |
| 5 | Language learning (5) | `convo_craft`, `brazilian-bites`, `worldly-words`, `fala-comigo-ai-tutor`, `go-accenter` | blue |
| 6 | Computer vision (4) | `climbing-wire`, `holo-table`, `abyss`, `pose-tools` | pink |
| 7 | Travel / Maps (2) | `trip-me-up`, `places-tools` | cyan |

**CSS changes:**
- Remove `overflow: hidden` + `height: 100%` from `html, body` to enable vertical scroll
- Change `.bubble-stage` from `flex: 1` to `height: 1000px`
- Reduce `--bubble-size` from `140px` to `120px` (5 bubbles fit across 700px stage)
- Replace 4 old project color vars (`--c1/c2/c3/c4`) with 7 group color vars (`--cg-*`)
- Replace 4 per-ID bubble rules with 23 covering all projects

**HTML changes:**
- Replace 4 placeholder bubbles with 23 real project bubbles across 7 rows


# setup the main site for pitrified.github.io

## overview

i have created the repo /home/pmn/repos/pitrified.github.io/README.md
and i want to move the site overview /home/pmn/repos/linux-box-cloudflare/sites/overview/index.html in that one, so that it is shown in https://pitrified.github.io/ and not in https://pitrified.github.io/linux-box-cloudflare/

the /home/pmn/repos/linux-box-cloudflare/sites/overview/index.html can still exist, but its content will change to link to the actual apps served in the box. in a future release, leave it as is for now.

can the github.io site support multiple pages?
how? are they markdown, html, mix?
can these pages share css/js assets?

if so, we want a landing page with a few high level bubbles
* AI/simulation -> /simulation
* recipe domain -> /recipes
* language learning -> /language-learning
* ... the others from the overview
* libraries -> /libraries # an additional one where the `*-tools` repos are listed with a graph, plus the other "core" libraries. so like `lang-tools` bubble will appear both in the language learning page and in the libraries page
* about me -> /about

and in the specific pages we have the other bubbles of the project in that category,
or whatever content we want (eg for the about page we can have a timeline of my life, or something like that)

---

## research

### current state

- **`pitrified.github.io` repo** - exists, essentially empty (just `README.md`, one "Initial commit"). Because the repo is named `<user>.github.io`, it is a GitHub **user site**, served at the **domain root** `https://pitrified.github.io/`. This is exactly what we want.
- **`linux-box-cloudflare/sites/overview/`** - the bubble site (`index.html` + `style.css` + `script.js`). It is deployed by [.github/workflows/deploy-site-overview.yml](../../../.github/workflows/deploy-site-overview.yml) to that repo's **project Pages**, which serve under `https://pitrified.github.io/linux-box-cloudflare/`. This is the `/linux-box-cloudflare/` path the overview note wants to move away from.
- **`linux-box-cloudflare/sites/landing/`** - separate, simpler "local hub" page (app cards for box services). This is the one whose role the overview will eventually take over (link to box apps). Leave as-is for now per the note.

So the move is: copy the bubble site into the `pitrified.github.io` repo root → it shows at the root URL. The two Pages sites are independent and can coexist; the `linux-box-cloudflare` project Pages can be left or disabled later - not in scope now.

### Q: can the github.io site support multiple pages? how?

**Yes.** GitHub Pages serves any static file tree. Each file/folder maps to a URL:

- `index.html` → `https://pitrified.github.io/`
- `about/index.html` → `https://pitrified.github.io/about/` (clean URL, recommended)
- `about.html` → `https://pitrified.github.io/about`

Because this is a **user site served at the domain root**, root-absolute links like `/recipes/`, `/libraries/`, `/assets/style.css` work everywhere and are stable regardless of nesting. (On a project site you'd have to prefix `/repo-name/`; we avoid that entirely here.)

Sub-pages need no special config - just create the folders. **Publishing source:** simplest is Pages → "Deploy from a branch" → `main` / root. No build step, no Actions workflow needed (the repo *is* the site). Push to `main` = publish.

### Q: markdown, html, or mix?

All three. By default GitHub Pages runs **Jekyll**, which:
- serves raw `.html`/`.css`/`.js` untouched,
- converts `.md` files that have YAML front matter into HTML.

Our overview is hand-crafted HTML/CSS/JS, so Markdown buys us nothing and Jekyll can cause surprises (it ignores files/folders starting with `_`, and adds a build step). **Recommendation: add an empty `.nojekyll` file at the repo root to disable Jekyll** and serve the tree verbatim. We stay pure static HTML. (Markdown remains an option later for prose pages like /about if desired - but we can do those in HTML too.)

ANSWER: ok, use `.nojekyll`

### Q: can pages share css/js assets?

**Yes.** Put shared files in one folder, e.g. `/assets/`, and reference them with root-absolute paths:

```html
<link rel="stylesheet" href="/assets/style.css" />
<script src="/assets/bubbles.js"></script>
```

Every page (root and sub-pages) uses the identical path. One stylesheet, one renderer, no duplication.

### the duplication problem (and a clean solution)

The bubbles repeat across pages (`lang-tools` on both `/language-learning` and `/libraries`, `places-tools` on `/travel` and `/libraries`, etc.). Hand-writing the same bubble HTML in multiple files is error-prone.

**Recommended approach: data-driven rendering.** Define every project once in a JS data file with a `categories` array, then a small renderer builds the bubbles on each page by filtering on category. Cross-listing becomes "add a second tag." This reuses the spirit of the existing `script.js` and keeps a single source of truth.

```
/assets/projects.js   // const PROJECTS = [{ id, name, desc, tags, url, categories:[...] }, ...]
/assets/bubbles.js    // renderProjects(category) -> injects .bubble nodes, then runs float stagger
/assets/style.css     // shared (lifted from the current overview style.css)
```

Each sub-page is then a thin shell: `<div class="bubble-stage" data-category="recipes"></div>` + the shared script.

ANSWER: great, nice data driven approach

(Alternative: static duplicated HTML per page. Simpler to read, but every project edit touches N files and cross-listing is manual. Not recommended given the repetition.)

### layout note

The current overview uses **absolute hand-placed coordinates** (`--x` / `--y` on a fixed 1400px stage) to pack ~30 bubbles. Category pages have far fewer bubbles, so a **responsive auto-flow / grid layout** will look better and need no manual coordinates. Plan to add a flow layout for sub-pages while keeping the dense hand-placed map for the root landing only if we want to preserve it - but more likely the **root landing becomes the small set of category bubbles**, and the dense all-projects map is dropped (or kept as a hidden "/all" page).

ANSWER: great, add hidden "/all" with all bubbles, that's neat

---

## category mapping

Top-level bubbles on the landing page (from the overview groups + the requested extras):

| landing bubble        | URL                  | source group / contents |
|-----------------------|----------------------|-------------------------|
| AI / simulation       | `/simulation`        | lAIfe |
| recipes               | `/recipes`           | kit-hub, recipamatic, recipinator, cookbook |
| language learning     | `/language-learning` | lang-tools*, convo-craft, br-bites, worldly-words, fala-comigo, go-accenter |
| travel / maps         | `/travel`            | places-tools*, trip-me-up |
| extended reality      | `/xr`                | pose-tools*, climbing-wire, holo-table, abyss |
| infrastructure / tools| `/infra`             | linux-box, dotfiles, repomgr, github.io, tg-bot |
| libraries             | `/libraries`         | the `*-tools` (lang-tools, places-tools, pose-tools, fastapi-tools, py-tools) + core libs (llm-core, media-dl, py-template) + interleaver - shown **with a dependency graph** |
| about me              | `/about`             | timeline / bio (free-form content, not bubbles) |

`*` = cross-listed (also appears on `/libraries`). The `categories` array in `projects.js` encodes this - e.g. `lang-tools` → `["language-learning", "libraries"]`.

**Open questions to confirm before building (see plan step 0):**
- exact landing bubble set & grouping (epub `interleaver` and `tg-bot` have no obvious top-level home - fold into libraries / infra?)
    ANSWER: new category `/misc` for epub. `tg-bot` can go under infra.
- the `/libraries` "graph": static SVG/diagram, or interactive (e.g. a small force/dependency graph)? what relationships does it show - repo→repo dependencies?
    ANSWER: start with a static SVG graph, showing repo→repo dependencies. Can evolve into interactive later if desired.
    RESOLVED - edges are auto-derived, no manual list. See "dependency-graph data source" below.
- `/about` content: timeline of what (life / projects / career)?
    ANSWER: timeline of life + projects together, vertical list with dates on the left and events

---

## dependency-graph data source (the `/libraries` SVG)

The repo→repo edges are **not** hand-written - they are derived from each repo's `pyproject.toml`
git dependencies by **repomgr**, which already tracks every repo in
[configs/repomgr/repos.toml](../../../configs/repomgr/repos.toml).

- Capability: [`repomgr.deps.build_dep_graph(configs, tracked)`](../../../../repomgr/src/repomgr/deps.py) - a pure
  function returning `{repo_name: [dep_repo_names]}`, parsed from git-sourced deps of the form
  `name @ git+ssh://…/<repo>@<tag>`. CLI equivalent: `repomgr dep-graph --config <path>`.
- A small **generator script** imports `load_config` + `build_dep_graph`, dedupes edges, maps
  repomgr repo names → bubble ids, and writes `assets/graph.json`. We then render a **static SVG**
  from that (committed). Regenerating after dep changes is one command.

**Current real graph (deduped), run 2026-06-11** - `llm-core` and `fastapi-tools` are the two hub libs:

```
kit-hub                  → llm-core, media-downloader, fastapi-tools
laife                    → llm-core
lang-tools               → llm-core, fastapi-tools
media-downloader         → llm-core, fastapi-tools     # media-dl bubble
places-tools             → fastapi-tools
python-project-template  → fastapi-tools               # py-template bubble
```

**Caveats (accepted):**
- **Python-only edges.** Only git deps in `pyproject.toml` are seen. JS/Go/Jekyll repos
  (worldly-words, br-bites, fala-comigo, go-accenter, cookbook) and currently-unreferenced libs
  (`python-tools`/py-tools, `pose-tools`) appear as **isolated nodes**. Accurate - the graph is the
  Python-lib ecosystem.
- **Dedup required** (`media-downloader → llm-core` appears 4× across optional-dep groups).
- **No `repos.toml` changes needed** - all repos already tracked and clonable.
- **Name bridging:** repomgr names differ from bubble ids (`media-downloader`=media-dl,
  `convo_craft`=convo-craft, `python-tools`=py-tools, `python-project-template`=py-template).
  Each entry in `projects.js` carries a `repo` field to bridge id ↔ repomgr name.

---

## proposed repo structure (`pitrified.github.io`)

```
pitrified.github.io/
├── .nojekyll                 # disable Jekyll, serve verbatim
├── index.html                # landing: 9 category bubbles + links
├── simulation/index.html     # thin shell, data-category="simulation"
├── recipes/index.html
├── language-learning/index.html
├── travel/index.html
├── xr/index.html
├── misc/index.html           # epub interleaver (catch-all)
├── infra/index.html          # incl. tg-bot
├── libraries/index.html      # *-tools + core libs + static dependency SVG
├── about/index.html          # vertical life+projects timeline (dates left, events right)
├── all/index.html            # hidden: full hand-placed bubble map (current overview layout)
├── assets/
│   ├── style.css             # shared (from current overview style.css)
│   ├── projects.js           # single source of truth: projects, categories, --x/--y, repo name, tags
│   ├── bubbles.js            # renderer + float stagger (evolves current script.js)
│   ├── graph.json            # generated repo→repo dep edges (from repomgr)
│   └── graph.svg             # static dependency graph rendered from graph.json
├── tools/
│   └── gen_graph.py          # imports repomgr.deps.build_dep_graph → writes graph.json (+ svg)
└── README.md
```

Landing bubbles (9): simulation, recipes, language-learning, travel, xr, misc, infra, libraries, about.

Pages settings: source = `main` / root. Push to publish.

ANSWER: looks good, let's do it

---

## plan

Scope is confirmed (all ANSWER/RESOLVED tags above). Build order:

1. **Shared foundation in `pitrified.github.io`**: add `.nojekyll`; create `assets/` - port `style.css`
   from the current overview; build `projects.js` as the single source of truth (every project with
   `id, name, desc, tags, url, categories[], repo, x, y`, the `--x/--y` taken from the current
   overview for the `/all` map); write `bubbles.js` (`renderProjects(category)` → injects `.bubble`
   nodes + float stagger, evolving the current `script.js`).
2. **Landing `index.html`**: 9 category bubbles (simulation, recipes, language-learning, travel, xr,
   misc, infra, libraries, about) linking to the sub-pages.
3. **Category sub-pages** as thin shells using the shared renderer + responsive flow layout:
   `simulation`, `recipes`, `language-learning`, `travel`, `xr`, `misc` (interleaver), `infra`
   (incl. tg-bot). Cross-listed projects (`lang-tools`, `places-tools`, `pose-tools`) tagged into
   both their category and `libraries` via `categories[]`.
4. **`/all`** (hidden): reproduce the current dense hand-placed overview map, rendered from the same
   `projects.js` using each project's `x/y`.
5. **Dependency graph**: write `tools/gen_graph.py` (imports `repomgr.config.load_config` +
   `repomgr.deps.build_dep_graph`, dedupes edges, maps repomgr names → bubble ids) → `assets/graph.json`;
   render a static `assets/graph.svg` from it. Build **`/libraries`**: the `*-tools` + core lib bubbles
   plus the embedded SVG.
6. **`/about`**: vertical timeline (dates left, life+project events right), hand-authored HTML.
7. **Enable Pages** (settings → Pages → deploy from `main` / root), push, verify root + every
   sub-page + `/all` + shared assets + the SVG resolve at `https://pitrified.github.io/...`.
8. *(future, not now)* repurpose `linux-box-cloudflare/sites/overview/` to link to the actual box
   apps; decide whether to disable the `linux-box-cloudflare` project Pages so nothing lingers at
   `/linux-box-cloudflare/`.

## sources

- [Creating a GitHub Pages site - GitHub Docs](https://docs.github.com/en/pages/getting-started-with-github-pages/creating-a-github-pages-site)
- [About GitHub Pages and Jekyll - GitHub Docs](https://docs.github.com/en/pages/setting-up-a-github-pages-site-with-jekyll/about-github-pages-and-jekyll)
- [Configuring a publishing source for your GitHub Pages site - GitHub Docs](https://docs.github.com/en/pages/getting-started-with-github-pages/configuring-a-publishing-source-for-your-github-pages-site)
- [GitHub Pages for a repo with multiple subfolders - community discussion #58276](https://github.com/orgs/community/discussions/58276)

# repomgr - Implementation Plan

## Context

`repomgr` is a local CLI tool that manages a fleet of Python repos on a single Linux box.
It lives inside `linux-box-cloudflare/tools/repomgr/` and is bootstrapped from
`python-project-template`.

It supersedes and absorbs the standalone `update_git_deps.py` script written earlier.

---

## Repository layout

```
linux-box-cloudflare/
└── tools/
    └── repomgr/
        ├── pyproject.toml
        ├── ruff.toml
        ├── .python-version
        ├── repos.toml          # config (committed - relative paths only)
        ├── repos.toml.example  # annotated example for reference
        ├── repos.state.json    # generated, gitignored
        └── src/
            └── repomgr/
                ├── __init__.py
                ├── config.py
                ├── state.py
                ├── git.py
                ├── deps.py
                ├── update.py
                ├── manager.py
                ├── health.py
                ├── renderer.py
                └── cli.py
```

---

## `repos.toml` schema

### `[settings]`

| Field            | Type   | Default          | Description                                      |
|------------------|--------|------------------|--------------------------------------------------|
| `base_path`      | str    | `"~/repos"`      | Base directory; all repo paths resolve from here |
| `default_test_cmd` | str  | `"uv run pytest"`| Test command used when a repo does not override  |
| `state_file`     | str    | `"./repos.state.json"` | Path to state file, relative to `repos.toml` |

### `[[repo]]`

| Field        | Type        | Required | Default              | Description                                           |
|--------------|-------------|----------|----------------------|-------------------------------------------------------|
| `name`       | str         | yes      | -                    | Unique identifier; also used as the folder name       |
| `remote`     | str         | yes      | -                    | Git remote URL - SSH or HTTPS, no assumptions made    |
| `roles`      | list[str]   | yes      | -                    | Any combination of `"source"` and `"consumer"`        |
| `auto_merge` | bool        | no       | `false`              | Whether to fast-forward local main after fetch        |
| `test_cmd`   | str \| null | no       | settings default     | Per-repo override for the test command                |
| `path`       | str \| null | no       | `base_path/<name>`   | Explicit absolute path override for non-standard layouts |

### Example `repos.toml`

```toml
[settings]
base_path        = "~/repos"
default_test_cmd = "uv run pytest"
state_file       = "./repos.state.json"

[[repo]]
name        = "llm-core"
remote      = "git@github.com:Pitrified/llm-core.git"
roles       = ["source"]
auto_merge  = true

[[repo]]
name        = "fastapi-tools"
remote      = "git@github.com:Pitrified/fastapi-tools.git"
roles       = ["source"]
auto_merge  = true

[[repo]]
name        = "recipamatic"
remote      = "git@github.com:Pitrified/recipamatic.git"
roles       = ["consumer"]
auto_merge  = false

[[repo]]
name        = "some-exception"
remote      = "git@github.com:Pitrified/some-exception.git"
roles       = ["consumer"]
path        = "~/projects/some-exception"   # override when name != folder name
```

---

## Pydantic models (`config.py`)

`config.py` is the only module that reads `repos.toml`. It returns clean Pydantic models.
Nothing downstream touches TOML or raw dicts.

```
Settings
  base_path: Path          # expanded (~ resolved)
  default_test_cmd: str
  state_file: Path         # expanded, resolved relative to repos.toml location

RepoConfig
  name: str
  remote: str              # plain string, no validation of SSH vs HTTPS
  roles: list[Role]        # Role = Enum("source", "consumer")
  auto_merge: bool
  test_cmd: str            # resolved: per-repo override OR settings default
  path: Path               # resolved: explicit override OR base_path / name

  # computed after dep-graph pass (populated by deps.py at startup)
  deps: list[str]          # names of other tracked repos this one depends on

RepomgrConfig
  settings: Settings
  repos: list[RepoConfig]
  repos_by_name: dict[str, RepoConfig]   # convenience index
```

`config.py` exposes one public function: `load_config(path: Path) -> RepomgrConfig`.

---

## State model (`state.py`)

### Design principle

`StateStore` is a connector. Its public API is stable. The backing implementation
(JSON today, SQLite later) is an internal detail. No other module imports JSON or
SQLite - they all go through `StateStore`.

### `RepoState` dataclass

```
RepoState
  name: str

  # populated after fetch
  last_fetch_at: datetime | None
  last_seen_main_sha: str | None       # SHA of origin/main after last fetch
  new_tags_since_last_fetch: list[str] # tags not seen in previous fetch

  # populated after update-deps run
  last_update_run_at: datetime | None
  last_update_result: str | None       # "ok" | "failed_tests" | "skipped" | "no_updates"

  # populated after test run
  last_test_run_at: datetime | None
  last_test_passed: bool | None
```

### `StateStore` public API

```python
class StateStore:
    def __init__(self, path: Path): ...
    def get(self, name: str) -> RepoState: ...          # returns empty RepoState if missing
    def save(self, state: RepoState) -> None: ...
    def get_all(self) -> list[RepoState]: ...
    def save_all(self, states: list[RepoState]) -> None: ...
```

`get()` never raises for a missing key - it returns a `RepoState` with all fields `None`.
This makes callers simpler: no existence checks required.

---

## `git.py` - pure subprocess layer

All git operations are functions here. No business logic, no config objects, no state.
Every function takes a `cwd: Path` as its first argument.

Functions to implement:

```
current_branch(cwd) -> str
is_clean(cwd) -> bool
is_behind_remote(cwd, branch="main") -> bool
is_ahead_of_remote(cwd, branch="main") -> bool
has_diverged(cwd, branch="main") -> bool
fetch(cwd) -> FetchResult          # new tags, new branches, commits added to origin/main
fast_forward(cwd, branch="main") -> None
clone(remote: str, dest: Path) -> None
list_tags(cwd) -> list[str]        # sorted by version descending
list_stale_branches(cwd) -> list[str]   # merged into main or gone from remote
delete_branch(cwd, branch: str) -> None
create_branch(cwd, name: str) -> None
checkout(cwd, ref: str) -> None
merge_ff_only(cwd, ref: str) -> None
commit(cwd, message: str, paths: list[Path]) -> None
push(cwd, branch: str) -> None
delete_remote_branch(cwd, branch: str) -> None
get_main_sha(cwd) -> str

FetchResult:
  new_tags: list[str]
  new_branches: list[str]
  main_advanced_by: int            # number of new commits on origin/main
  new_commit_log: list[str]        # short log lines of those commits
```

`fetch()` does the full diff before/after `git fetch --tags` to compute `FetchResult`.

---

## `deps.py` - dependency graph

Responsibilities:
1. Parse `pyproject.toml` of each consumer repo and extract git-sourced deps.
2. Cross-reference against `repos_by_name` to identify which deps are "tracked".
3. Resolve the latest semver tag from the dep's local clone (via `git.list_tags()`).
4. Build the full dependency graph.
5. Provide topological sort for update ordering.

### `GitDep` dataclass

```
GitDep
  name: str
  current_tag: str
  extras: str           # e.g. "[all]" or ""
  raw_line: str         # original string in pyproject.toml, for in-place replacement
  latest_tag: str       # populated after resolution
  needs_update: bool    # latest_tag != current_tag
```

### Public API

```python
def parse_git_deps(pyproject_path: Path, tracked: dict[str, RepoConfig]) -> list[GitDep]: ...
def resolve_latest_tags(deps: list[GitDep], configs: dict[str, RepoConfig]) -> None: ...
def build_dep_graph(configs: list[RepoConfig]) -> dict[str, list[str]]: ...
    # returns {repo_name: [dep_name, ...]} for tracked deps only
def topological_order(graph: dict[str, list[str]]) -> list[str]: ...
    # sources first, deepest consumers last
def update_pyproject(pyproject_path: Path, dep: GitDep) -> None: ...
    # in-place string replacement, preserves formatting
```

`build_dep_graph()` is called once at startup by `cli.py` and the result is stored on
`RepomgrConfig` (or passed down explicitly - no global state).

---

## `health.py` - traffic-light scoring

`HealthStatus` is an enum: `GREEN | YELLOW | RED`.

### Inputs

`compute_health(config: RepoConfig, state: RepoState, live: LiveRepoStatus) -> HealthReport`

`LiveRepoStatus` is a small dataclass populated by cheap git calls at status-check time:
```
LiveRepoStatus
  branch: str
  is_clean: bool
  is_behind: bool
  is_ahead: bool
  has_diverged: bool
  repo_exists: bool
```

### Scoring rules

| Condition                              | Contribution |
|----------------------------------------|--------------|
| Repo not on disk                       | RED (immediate, stops here) |
| Diverged from remote                   | RED          |
| Not on main                            | YELLOW       |
| Dirty working tree                     | YELLOW       |
| Behind remote (and auto_merge = false) | YELLOW       |
| Last test failed                       | YELLOW       |
| Never fetched                          | YELLOW       |
| Deps behind latest (consumer role)     | YELLOW       |
| All clear                              | GREEN        |

RED overrides YELLOW. Any YELLOW prevents GREEN.

### `HealthReport`

```
HealthReport
  status: HealthStatus
  reasons: list[str]     # human-readable list of contributing conditions
```

---

## `renderer.py` - terminal frontend

`renderer.py` is the only module that imports `rich`. It takes data structures
(no git calls, no file IO) and formats them for terminal output.

### Design principle

`renderer.py` reads from `state.json` + freshly computed `HealthReport`s.
It does not generate data - it only formats it. Swapping to a web dashboard later
means replacing this one file.

### Functions

```python
def render_status(reports: list[StatusRow]) -> None: ...
def render_fetch_result(name: str, result: FetchResult) -> None: ...
def render_update_summary(results: list[RepoResult]) -> None: ...
def render_dep_graph(graph: dict[str, list[str]]) -> None: ...
def render_stale_branches(repo_name: str, branches: list[str]) -> None: ...
```

`StatusRow` is a flat dataclass assembling everything needed for one row in the dashboard:
```
StatusRow
  name: str
  health: HealthReport
  live: LiveRepoStatus
  state: RepoState
  deps_behind: list[str]    # names of tracked deps with newer tags available
```

---

## `manager.py` - fetch, clone, status, stale branches

Orchestrates operations using `git.py`, `state.py`, `health.py`, `deps.py`, `renderer.py`.

### `fetch_all(config, store)`
For each repo:
1. If not on disk → skip with warning.
2. Call `git.fetch()` → `FetchResult`.
3. Update `RepoState` (last_fetch_at, last_seen_main_sha, new_tags_since_last_fetch).
4. If `auto_merge=true` AND on main AND clean AND not diverged → `git.fast_forward()`.
5. Call `renderer.render_fetch_result()`.
6. Save state.

### `clone_missing(config)`
For each repo not on disk: `git.clone(remote, path)`, print result.

### `status_all(config, store, dep_graph)`
For each repo:
1. Gather `LiveRepoStatus` (cheap git calls or defaults if not on disk).
2. Resolve `deps_behind` via `deps.py`.
3. Compute `HealthReport` via `health.py`.
4. Assemble `StatusRow`.
5. Pass all rows to `renderer.render_status()`.

Does not write to state - read-only.

### `stale_branches(config, store)`
For each repo: call `git.list_stale_branches()`, prompt interactively, call
`git.delete_branch()` for confirmed ones.

---

## `update.py` - dep update flow

Absorbed from `update_git_deps.py`. Refactored to use the shared `git.py`, `deps.py`,
`state.py`, `renderer.py` modules.

### Flow per consumer repo

1. Health pre-check (must be on main, clean, not behind remote).
2. Parse git deps → resolve latest tags.
3. If no updates needed → skip.
4. Create branch `deps/update_<YYYYMMDD_HHMMSS>`.
5. Apply updates to `pyproject.toml`.
6. Run test command.
   - **Pass**: commit, merge `--ff-only` to main, delete branch, push.
   - **Fail**: commit WIP state to branch, leave branch, move to next repo.
7. Update `RepoState` (last_update_run_at, last_update_result, last_test_run_at, last_test_passed).
8. Save state.

### Flags

| Flag          | Effect                                               |
|---------------|------------------------------------------------------|
| `--dry-run`   | Print what would change, no writes                   |
| `--no-tests`  | Skip test suite, merge unconditionally               |
| `--repo NAME` | Run only for the named consumer repo                 |

---

## `cli.py` - typer entrypoint

Thin layer only. Loads config, builds dep graph, instantiates `StateStore`,
delegates to the appropriate module. No business logic here.

### Commands

```
repomgr status              # dashboard across all repos
repomgr fetch               # fetch all, report, auto-merge where configured
repomgr clone-missing       # clone repos not on disk
repomgr update-deps         # run dep update flow across all consumers
repomgr stale-branches      # list and interactively delete stale branches
repomgr dep-graph           # print the dependency tree
```

### Startup sequence (all commands)

1. Load `repos.toml` → `RepomgrConfig`.
2. Build dep graph (populate `RepoConfig.deps` for each repo).
3. Instantiate `StateStore(settings.state_file)`.
4. Dispatch to subcommand.

---

## `pyproject.toml` key decisions

- Build backend: `hatchling` + `hatch-vcs` (version from git tags).
- `dynamic = ["version"]`, `[tool.hatch.version] source = "vcs"`.
- `[tool.hatch.build.hooks.vcs] version-file = "src/repomgr/_version.py"`.
- `_version.py` gitignored.

### Dependencies

```toml
[project]
dependencies = [
    "loguru",
    "pydantic>=2",
    "tomllib",       # stdlib on 3.11+; add tomli as fallback for <3.11
    "typer",
    "rich",
]

[dependency-groups]
test = ["pytest", "pytest-asyncio"]
lint = ["ruff", "pyright[nodejs]", "pre-commit"]
```

No PyPI publishing. Installed locally via `uv pip install -e .` or `uv sync`.

### Scripts

```toml
[project.scripts]
repomgr = "repomgr.cli:app"
```

---

## `repos.state.json` format

Top-level: a dict keyed by repo name. Each value is a serialized `RepoState`.
Dates stored as ISO 8601 strings.

```json
{
  "llm-core": {
    "name": "llm-core",
    "last_fetch_at": "2026-03-27T09:14:00",
    "last_seen_main_sha": "abc1234",
    "new_tags_since_last_fetch": [],
    "last_update_run_at": null,
    "last_update_result": null,
    "last_test_run_at": null,
    "last_test_passed": null
  }
}
```

`StateStore` reads this file at instantiation and writes it atomically (write to
`.tmp` then `rename`) after every `save()` or `save_all()` call.

---

## Module dependency graph

```
cli.py
 ├── config.py          (no internal deps)
 ├── state.py           (no internal deps)
 ├── git.py             (no internal deps)
 ├── deps.py            → git.py, config.py
 ├── health.py          → config.py, state.py
 ├── renderer.py        → health.py, state.py, git.py (FetchResult only)
 ├── manager.py         → git.py, state.py, health.py, deps.py, renderer.py
 └── update.py          → git.py, state.py, deps.py, renderer.py
```

No circular dependencies. `cli.py` is the only module that imports from all others.

---

## Implementation order

1. `config.py` - foundation, everything depends on it. Write tests first.
2. `git.py` - pure subprocess, manually testable against any local repo.
3. `state.py` - simple JSON connector. Write tests against a tmp file.
4. `deps.py` - builds on `git.py` and `config.py`.
5. `health.py` - pure function, easy to unit test with mocked inputs.
6. `renderer.py` - rich formatting, no logic to test.
7. `manager.py` - integration layer.
8. `update.py` - port from existing `update_git_deps.py`, adapt to new modules.
9. `cli.py` - wire everything together.

---

## Deferred / out of scope for v1

- SQLite backend for `StateStore` (JSON is sufficient, swap later).
- Web/TUI dashboard frontend (renderer.py is the seam for this).
- Cron/scheduled runs (run manually or via a simple shell cron calling `repomgr fetch`).
- GitHub Actions integration.
- `python-tools` / `pmn-core` extraction (separate package, separate plan).

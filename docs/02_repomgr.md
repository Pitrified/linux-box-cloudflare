# Repo Management with repomgr

This document explains how [repomgr](https://github.com/Pitrified/repomgr) is used to manage the fleet of Python repos on this box.

---

## What repomgr does

`repomgr` tracks a set of git repos defined in a `repos.toml` file. It provides:

- A health dashboard across all repos (git status, ahead/behind, dirty files).
- Fetching all remotes in one command and reporting divergences.
- Cloning any repo that is not yet on disk.
- Printing the source/consumer dependency graph.
- Bumping git-sourced dependencies across consumer repos and running tests.
- Listing and interactively deleting stale branches.

---

## Installation

`repomgr` is cloned at `~/repos/repomgr`. Install its dependencies with:

```bash
cd ~/repos/repomgr
uv sync --group dev
```

The CLI entry point is available as `repomgr` (via the `repomgr.cli:app` script registered in `pyproject.toml`). If `uv` scripts are not on `$PATH`, invoke it with:

```bash
uv run --project ~/repos/repomgr repomgr <command>
```

---

## Config location

The `repos.toml` for this workspace lives at:

```
~/repos/linux-box-cloudflare/configs/repomgr/repos.toml
```

It is kept inside `linux-box-cloudflare` (not inside the `repomgr` package) because it is a workspace-specific configuration. The state file (`repos.state.json`) is written alongside it, in the same directory.

Pass the path explicitly on every invocation with `--config` (or `-c`):

```bash
repomgr status --config ~/repos/linux-box-cloudflare/configs/repomgr/repos.toml
```

---

## Common commands

| Command | What it does |
|---|---|
| `repomgr status` | Health dashboard - dirty files, ahead/behind, branch |
| `repomgr fetch` | Fetch all remotes; report divergences; auto-merge sources when configured |
| `repomgr clone-missing` | Clone repos listed in `repos.toml` that are not yet on disk |
| `repomgr dep-graph` | Print the source/consumer dependency tree |
| `repomgr update-deps` | Bump git deps, run tests, auto-merge or leave a branch for review |
| `repomgr stale-branches` | List and interactively delete old branches |

All commands accept `--config` / `-c` to point at a non-default `repos.toml`.

---

## Dependency graph

The repos in this workspace form the following dependency chain:

```
llm-core          (source)
fastapi-tools     (source)
    |
    +-- media-downloader  (source + consumer)
    |       |
    |       +-- kit-hub   (consumer)
    |
    +-- kit-hub           (consumer, also depends on llm-core)

llm-core
    |
    +-- laife             (consumer)
    |
    +-- media-downloader  (source + consumer)
    |
    +-- kit-hub           (consumer)
```

Sources (`llm-core`, `fastapi-tools`, `media-downloader`) have `auto_merge = true`, so `repomgr update-deps` will merge a successful dep bump automatically. Consumer-only repos (`laife`, `kit-hub`) stay `auto_merge = false` - updates open a branch for manual review.

Standalone repos (`linux-box-cloudflare`, `repomgr`, `tg-central-hub-bot`, `python-project-template`, `recipamatic`, `recipinator`, `cookbook`, `convo_craft`) are tracked for `status` and `fetch` but are not part of the git-dep chain.

---

## SSH remote requirement

This workspace sets `transport = "ssh"` in `[settings]`, so repomgr derives SSH clone URLs (`git@github.com:...`). Verify that an SSH key for `github.com` is loaded:

```bash
ssh -T git@github.com
```

Any repo that was cloned over HTTPS can be switched with:

```bash
cd ~/repos/<repo-name>
git remote set-url origin git@github.com:Pitrified/<repo-name>.git
```

---

## Adding a new repo

1. Append a `[[repo]]` entry to `configs/repomgr/repos.toml`:

```toml
[[repo]]
name   = "new-repo"
roles  = ["consumer"]
```

The clone URL is derived from the global `[settings]` `owner`/`host`/`transport`
and the repo `name` - no `remote` URL is set per repo. Add `owner = "..."` to
the entry only if it lives under a different owner, or `repo_name = "..."` if
the GitHub repo name differs from the local `name`.

2. Clone it if not already on disk:

```bash
repomgr clone-missing --config ~/repos/linux-box-cloudflare/configs/repomgr/repos.toml
```

3. Run `status` to confirm it is found and healthy:

```bash
repomgr status --config ~/repos/linux-box-cloudflare/configs/repomgr/repos.toml
```

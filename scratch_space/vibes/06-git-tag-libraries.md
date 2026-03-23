# Make libraries installable with git tags

## Overview

in
`llm-core/scratch_space/02_core/08-release-migration.md`
we have a plan to make `llm-core` installable via git tags,
which lets consumers update their `pyproject.toml` to point to `llm-core` on GitHub.
there is a plan to write a `makefile` to let consumers momentarily point to a local version of `llm-core` to test `llm-core` when developing in sync `llm-core` and a consumer project.

please

1. write a clear documentation of this pattern in `linux-box-cloudflare/docs`
2. write a template `makefile` target that can be copied into consumer projects to enable the local development pattern
3. expand this pattern to `fastapi-tools` and `media-downloader`, which are also libraries used by multiple projects
4. write a precise plan of what these three libraries need to do to be installable via git tags
5. write a precise plan of what the consumer projects need to do to be able to install these libraries via git tags and use the local development pattern (look in the workspace for consumer projects that depend on these libraries)

## Plan: Git-tag installable libraries

Make `llm-core`, `fastapi-tools`, and `media-downloader` installable via git tags, and migrate
their consumers to pin against those tags using a Makefile-based local dev override pattern.

### Context

**Dependency graph**

```
llm-core        (leaf library, no internal deps)
fastapi-tools   (leaf library, no internal deps)
media-downloader  (library + consumer of llm-core and fastapi-tools)
laife             (consumer of llm-core)
```

**Current consumer pinning state**

| Consumer           | Dependency      | Current declaration                                                              |
| ------------------ | --------------- | -------------------------------------------------------------------------------- |
| `laife`            | `llm-core`      | `"llm-core[all] @ file:///home/pmn/repos/llm-core"` (hardcoded absolute path)    |
| `media-downloader` | `llm-core`      | `"llm-core>=0.1.0"` + `[tool.uv.sources]` local editable override committed      |
| `media-downloader` | `fastapi-tools` | `"fastapi-tools>=0.1.0"` + `[tool.uv.sources]` local editable override committed |

---

### Step 1 - Release llm-core v0.1.0

`llm-core` is a leaf library. Its `README.md` already documents the `git+https` install form and
its `CHANGELOG.md` documents `v0.1.0` (2026-03-21). It may already be tagged.

**Files:** `llm-core/pyproject.toml`

1. Add `[project.urls]` pointing at the GitHub repo:
   ```toml
   [project.urls]
   Repository = "https://github.com/pitrified/llm-core"
   ```
2. Check whether the `v0.1.0` tag already exists on `origin`:
   ```bash
   git -C /home/pmn/repos/llm-core tag -l
   git -C /home/pmn/repos/llm-core ls-remote --tags origin
   ```
3. If the tag is missing, create an annotated tag and push:
   ```bash
   cd /home/pmn/repos/llm-core
   git tag -a v0.1.0 -m "Release v0.1.0"
   git push origin v0.1.0
   ```
4. Verify the install works from the tag:
   ```bash
   uv pip install "llm-core[openai] @ git+https://github.com/pitrified/llm-core@v0.1.0"
   ```

---

### Step 2 - Release fastapi-tools v0.1.0

**Files:** `fastapi-tools/pyproject.toml`, `fastapi-tools/CHANGELOG.md` (new)

1. Add `[project.urls]` to `pyproject.toml`:
   ```toml
   [project.urls]
   Repository = "https://github.com/pitrified/fastapi-tools"
   ```
2. Create `CHANGELOG.md` modeled after `llm-core/CHANGELOG.md`. Minimum content:

   ```markdown
   # Changelog

   All notable changes to this project will be documented in this file.
   The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

   ## [0.1.0] - 2026-03-23

   ### Added

   - Initial release.
   ```

3. Create an annotated tag and push:
   ```bash
   cd /home/pmn/repos/fastapi-tools
   git add pyproject.toml CHANGELOG.md
   git commit -m "chore: add project urls and changelog for v0.1.0"
   git tag -a v0.1.0 -m "Release v0.1.0"
   git push origin main v0.1.0
   ```
4. Verify install:
   ```bash
   uv pip install "fastapi-tools @ git+https://github.com/pitrified/fastapi-tools@v0.1.0"
   ```

---

### Step 3 - Release media-downloader v0.1.0

`media-downloader` depends on the two libraries above; its own deps must point at tagged versions
before it can itself be tagged.

**Files:** `media-downloader/pyproject.toml`, `media-downloader/CHANGELOG.md` (new)

1. Add `[project.urls]` to `pyproject.toml`:
   ```toml
   [project.urls]
   Repository = "https://github.com/pitrified/media-downloader"
   ```
2. Replace all `"llm-core[whisper]>=0.1.0"`, `"llm-core[faster-whisper]>=0.1.0"`,
   `"llm-core[openai]>=0.1.0"`, and `"llm-core>=0.1.0"` with pinned git-tag forms.
   Example for one optional extras group:
   ```toml
   [project.optional-dependencies]
   stt-local-fast = [
       "llm-core[faster-whisper] @ git+https://github.com/pitrified/llm-core@v0.1.0",
   ]
   webapp = [
       "fastapi-tools @ git+https://github.com/pitrified/fastapi-tools@v0.1.0",
   ]
   llm-core-base = [
       "llm-core @ git+https://github.com/pitrified/llm-core@v0.1.0",
   ]
   ```
   Apply the same substitution to every group that references these two packages.
3. Remove the `[tool.uv.sources]` block (the two editable local overrides):
   ```toml
   # DELETE these lines from the committed pyproject.toml:
   [tool.uv.sources]
   fastapi-tools = { path = "../fastapi-tools", editable = true }
   llm-core = { path = "../llm-core", editable = true }
   ```
   Local dev is handled by the Makefile instead (Step 6).
4. Create `CHANGELOG.md` (same structure as Step 2).
5. Run `uv sync --all-extras` and the full test suite to confirm the tagged installs resolve:
   ```bash
   cd /home/pmn/repos/media-downloader
   uv sync --all-extras
   uv run pytest && uv run ruff check . && uv run pyright
   ```
6. Commit, tag, and push:
   ```bash
   git add pyproject.toml CHANGELOG.md
   git commit -m "chore: pin deps to git tags and add changelog for v0.1.0"
   git tag -a v0.1.0 -m "Release v0.1.0"
   git push origin main v0.1.0
   ```

---

### Step 4 - Migrate laife to git+https

`laife` currently uses a hardcoded absolute `file://` path that breaks on any machine other than
the author's.

**Files:** `laife/pyproject.toml`, `laife/Makefile` (new)

1. In `[project.dependencies]`, replace:
   ```toml
   "llm-core[all] @ file:///home/pmn/repos/llm-core",
   ```
   with:
   ```toml
   "llm-core[all] @ git+https://github.com/pitrified/llm-core@v0.1.0",
   ```
2. Run `uv sync` and the full test suite to confirm the tagged install resolves:
   ```bash
   cd /home/pmn/repos/laife
   uv sync
   uv run pytest && uv run ruff check . && uv run pyright
   ```
3. Add a `Makefile` with the local dev target (see Step 5 for the template).
4. Commit:
   ```bash
   git add pyproject.toml Makefile
   git commit -m "chore: pin llm-core to git tag and add dev makefile"
   ```

---

### Step 5 - Makefile template for consumer local dev

Each consumer gets a `Makefile` with targets that install a library in editable mode directly
into the venv. `uv sync` reverts to the pinned git version.

```makefile
LLM_CORE_PATH     ?= ../llm-core
FASTAPI_TOOLS_PATH ?= ../fastapi-tools
MEDIA_DL_PATH     ?= ../media-downloader

.PHONY: dev-llm-core dev-fastapi-tools dev-media-downloader

dev-llm-core: ## Install llm-core from a local editable path
	uv pip install -e "$(LLM_CORE_PATH)[all]"
	@echo "llm-core installed from $(LLM_CORE_PATH) - run 'uv sync' to revert"

dev-fastapi-tools: ## Install fastapi-tools from a local editable path
	uv pip install -e "$(FASTAPI_TOOLS_PATH)"
	@echo "fastapi-tools installed from $(FASTAPI_TOOLS_PATH) - run 'uv sync' to revert"

dev-media-downloader: ## Install media-downloader from a local editable path
	uv pip install -e "$(MEDIA_DL_PATH)[all]"
	@echo "media-downloader installed from $(MEDIA_DL_PATH) - run 'uv sync' to revert"
```

Usage:

```bash
make dev-llm-core                                  # uses ../llm-core (sibling folder)
make dev-llm-core LLM_CORE_PATH=~/dev/llm-core     # custom path
uv sync                                            # revert to pinned git tag version
```

Each consumer project only needs the Makefile target(s) relevant to its own dependencies. Copy
the relevant targets from the template above.

**Per consumer - which targets to include:**

| Consumer                         | Targets needed                      |
| -------------------------------- | ----------------------------------- |
| `laife`                          | `dev-llm-core`                      |
| `media-downloader` (as consumer) | `dev-llm-core`, `dev-fastapi-tools` |

---

### Step 6 - Write documentation

**File:** `linux-box-cloudflare/docs/git-tag-libraries.md` (new)

Write a single narrative doc covering:

1. **The pattern** - why internal libraries are pinned via git tags rather than PyPI or path refs.
2. **Library release checklist** - steps 1-3 above condensed into a repeatable checklist.
3. **Consumer setup** - how to update `pyproject.toml` from `file://` or `>=version` to `@ git+https://...@vX.Y.Z`.
4. **Local dev workflow** - copy the Makefile template, explain `make dev-X` / `uv sync` cycle.
5. **Tagging convention** - annotated tags, `vMAJOR.MINOR.PATCH`, push tags explicitly.

---

### Notes

1. `llm-core` v0.1.0 may already be tagged. Verify with `git tag -l` before creating a new tag to
   avoid overwriting.
2. The `[tool.uv.sources]` block in `media-downloader/pyproject.toml` is currently committed with
   local editable paths. Removing it changes the default resolution for anyone who clones the repo.
   This is intentional - the Makefile becomes the documented local dev entry point.
3. `laife` uses a hardcoded absolute path (`file:///home/pmn/repos/llm-core`) which is the most
   urgent migration - it silently breaks on any other machine.
4. `fastapi-tools` and `media-downloader` do not yet have GitHub URLs declared in `pyproject.toml`.
   Adding `[project.urls]` is a metadata improvement, not a prerequisite for git install.
5. Execution order is strict: tag `llm-core` first, then `fastapi-tools`, then update
   `media-downloader` deps and tag it, then update consumers.
6. After each library is tagged, verify the install with `uv pip install` before proceeding to the
   next step.

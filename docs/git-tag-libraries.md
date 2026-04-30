# Git-tag installable libraries

This document describes the pattern used to share internal Python libraries (`llm-core`,
`fastapi-tools`, `media-downloader`) across multiple projects without publishing to PyPI.

---

## The pattern

Libraries live in their own GitHub repositories. Consumer projects pin against a specific
annotated git tag using the PEP 440 direct URL syntax:

```toml
# pyproject.toml dependency entry
"llm-core[all] @ git+https://github.com/Pitrified/llm-core@v0.1.0"
```

`uv` resolves and installs this exactly like a PyPI package - no manual path management needed.

Why not PyPI? Publishing is overhead for internal libraries. Git tags give the same pinning
guarantees, are trivially cheap to create and query, and keep the entire history visible in the
repository.

Why not `file://` or `[tool.uv.sources]`? Absolute `file://` paths break on any machine that
is not the original author's box. Committed `[tool.uv.sources]` overrides silently change
resolution for everyone who clones the repo, making reproducible installs unreliable.

---

## Library release checklist

Repeat these steps each time a library needs a new release. Order matters: tag leaf libraries
before their consumers.

**Dependency order:**

1. `llm-core` (no internal deps)
2. `fastapi-tools` (no internal deps)
3. `media-downloader` (depends on `llm-core` and `fastapi-tools`)

### For each library

1. Update `[project.urls]` in `pyproject.toml` if not already present:

   ```toml
   [project.urls]
   Repository = "https://github.com/Pitrified/<repo-name>"
   ```

2. If the library's own `[project.dependencies]` or `[project.optional-dependencies]` contain
   direct URL references (i.e. it depends on another internal library via `@ git+https://...`),
   add the hatchling opt-in:

   ```toml
   [tool.hatch.metadata]
   allow-direct-references = true
   ```

   Hatchling rejects direct references at build time without this flag. Leaf libraries that only
   declare PyPI dependencies do not need it.

3. Append a new entry to `CHANGELOG.md` following Keep a Changelog format:

   ```markdown
   ## [X.Y.Z] - YYYY-MM-DD

   ### Added / Changed / Fixed / Removed

   - ...
   ```

4. Bump `version` in `[project]` to the new `X.Y.Z`.

5. Commit:

   ```bash
   git add pyproject.toml CHANGELOG.md
   git commit -m "chore: release vX.Y.Z"
   ```

6. Create an annotated tag and push:

   ```bash
   git tag -a vX.Y.Z -m "Release vX.Y.Z"
   git push origin main vX.Y.Z
   ```

7. Verify the install from the tag before updating consumers:

   ```bash
   uv pip install "llm-core[openai] @ git+https://github.com/Pitrified/llm-core@vX.Y.Z"
   ```

---

## Consumer setup

### Pinning to a git tag

In `[project.dependencies]` or `[project.optional-dependencies]`, write the full `@ git+https`
URL with the tag. Examples:

```toml
[project.dependencies]
# Simple dependency (no extras)
"fastapi-tools @ git+https://github.com/Pitrified/fastapi-tools@v0.1.0",

# Dependency with extras
"llm-core[all] @ git+https://github.com/Pitrified/llm-core@v0.1.0",

[project.optional-dependencies]
stt = [
    "llm-core[faster-whisper] @ git+https://github.com/Pitrified/llm-core@v0.1.0",
]
```

### Upgrading to a new tag

Change the tag suffix (`@v0.1.0` → `@v0.2.0`) in every dependency entry that references the
library, then run `uv sync`.

### Do not commit [tool.uv.sources] overrides

`[tool.uv.sources]` editable overrides are for local development only. Use the Makefile local
dev targets (below) instead of committing path overrides. Committing editable paths makes all
installs non-reproducible for other developers.

---

## Local development workflow

When you are working on a library and a consumer at the same time, you need to point the
consumer's venv at your local checkout rather than the pinned git tag.

Each consumer ships a `Makefile` with targets that do this. The targets use `uv pip install -e`
to install the library directly into the active venv without modifying `pyproject.toml`.
Running `uv sync` afterwards reverts to the pinned git tag.

### Template Makefile

Copy the targets that apply to your consumer's dependencies:

```makefile
LLM_CORE_PATH      ?= ../llm-core
FASTAPI_TOOLS_PATH ?= ../fastapi-tools
MEDIA_DL_PATH      ?= ../media-downloader

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

### Usage

```bash
# Use the library from a sibling directory (default)
make dev-llm-core

# Use a library from a custom path
make dev-llm-core LLM_CORE_PATH=~/dev/llm-core

# Revert to the pinned git tag version
uv sync
```

The `PATH ?= ../...` default assumes repos are checked out as siblings. Override on the command
line if your layout differs.

### Which targets to include per consumer

| Consumer           | Targets needed                      |
| ------------------ | ----------------------------------- |
| `laife`            | `dev-llm-core`                      |
| `media-downloader` | `dev-llm-core`, `dev-fastapi-tools` |

---

## Tagging conventions

- Always use **annotated** tags (`git tag -a`), not lightweight tags. Annotated tags carry the
  tagger identity, date, and message, which makes releases auditable.
- Tag format: `vMAJOR.MINOR.PATCH` (e.g. `v0.1.0`, `v1.0.0`).
- Push tags **explicitly**: `git push origin vX.Y.Z`. `git push` alone does not push tags.
- Never force-push or move an existing tag. Create a new patch version instead.

---

## Current library status

| Library            | Version | Tag pushed | GitHub URL                                      |
| ------------------ | ------- | ---------- | ----------------------------------------------- |
| `llm-core`         | 0.2.2   | yes        | <https://github.com/Pitrified/llm-core>         |
| `fastapi-tools`    | 0.1.0   | yes        | <https://github.com/Pitrified/fastapi-tools>    |
| `media-downloader` | 0.1.2   | yes        | <https://github.com/Pitrified/media-downloader> |

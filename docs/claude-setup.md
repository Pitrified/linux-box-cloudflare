# Claude Code setup pattern

How Claude Code is configured across the linux-box ecosystem, and how to wire up
a new repo. The key fact: **Claude Code only auto-loads `CLAUDE.md`. It does not
read `.github/copilot-instructions.md` or `AGENTS.md` on its own.**

## Layers

| Where | Scope | What it holds |
| --- | --- | --- |
| `~/.claude/CLAUDE.md` | every project on this box | truly general rules (e.g. no em dashes, match surrounding code) |
| `~/.claude/rules/<lang>.md` | files matching `paths:` frontmatter | language-specific rules, loaded only when relevant files are touched |
| `~/.claude/settings.json` | every project | read-only Bash permission allowlist |
| `<repo>/CLAUDE.md` | that repo | a one-line `@import` of the repo's canonical instructions |

General vs language-specific split: a rule like "no em dashes" is general and
lives in `~/.claude/CLAUDE.md`. A rule like "use `loguru`" or "run `uv run
pytest`" is Python-only and lives in `~/.claude/rules/python.md`.

## Per-language rules (`~/.claude/rules/`)

Each file is scoped with YAML frontmatter and loads into context only when Claude
reads a matching file - so the Go rules never pollute a Python session.

```markdown
---
paths:
  - "**/*.py"
  - "**/pyproject.toml"
---
# Python conventions
- Managed with uv; verify with `uv run pytest && uv run ruff check . && uv run pyright`
```

`python.md` exists today. Add `flutter.md`, `go.md`, `godot.md`, `js.md`, etc.
the same way when those projects need it.

## Wiring up a new repo

Create a `CLAUDE.md` at the repo root that imports the file you already maintain:

```markdown
@.github/copilot-instructions.md
```

That is the whole file. Copilot and Claude then read one source of truth and you
never maintain two copies. Add Claude-specific notes below the import if needed.
`@import` supports relative and absolute paths and nests up to 4 hops deep.

## Permissions (`~/.claude/settings.json`)

Lets Claude run safe read-only commands without prompting. Two safety rules:

- **Matching is prefix-based.** `Bash(git log:*)` allows `git log` with *any*
  arguments. So only allowlist verbs that have no destructive flag.
- **Footguns to never allowlist broadly:** `find:*` (enables `-delete` /
  `-exec`), `git branch:*` (enables `git branch -D`), `docker:*` /`xargs:*`
  (too broad). The allowlist uses `git branch` (exact, no args) for this reason.

`deny` always beats `allow`, and compound commands (`a && b`, `$(...)`) still
trigger a fresh prompt instead of inheriting an allow.

## References

- Memory / CLAUDE.md: https://code.claude.com/docs/en/memory
- Settings / permissions: https://code.claude.com/docs/en/settings

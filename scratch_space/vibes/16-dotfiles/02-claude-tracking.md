# dotfiles update

## overview

repo
/home/pmn/dotfiles
has some machinery to create symlinks pointing to configs in the repo,
so that the actual config files are in the repo and git can track them,
and in all machines the setup is the same.

claude settings should be in dotfiles as well
but we need to check
1. if there are any secrets in there first
2. how often is that file updated and by whom

## analysis

### what we track

Only three hand-written, portable files:

- `~/.claude/CLAUDE.md` - general user instructions
- `~/.claude/rules/python.md` - python rules (path-scoped)
- `~/.claude/settings.json` - prefs + read-only permission allowlist

### 1. secrets check

No secrets in any of the three. Scanned for key/token/secret/password/pem/
credential/api - nothing. `settings.json` only holds `model`/`theme`/`effortLevel`
and the permission allow/deny lists.

We deliberately do NOT track the whole `~/.claude/` folder. It also contains
`.credentials.json`, `history.jsonl`, `sessions/`, and `projects/` (auto-memory).
Symlinking the whole folder would both expose secrets and hide the real runtime
state behind a repo symlink. So we track the three files individually.

### 2. how often updated, by whom

- `CLAUDE.md`, `rules/python.md`: only edited by hand, deliberately. Safe to track.
- `settings.json`: also written by Claude Code itself. Key risk the user raised:
  if Claude writes via **atomic replace** (temp file + rename), it swaps the
  symlink for a real file holding NEWER content. A blind re-link would then back
  that file up to `~/.rcbackNN` and point the live config at the STALE repo copy,
  silently regressing it. (If Claude instead writes **in place** through the
  symlink, the repo file updates directly and there is no problem.)

  Handled two ways so it is safe regardless of which write mode Claude uses:
  1. `install.py` no longer silently reverts. Already-linked files are skipped
     (idempotent, no backup churn). If it finds a real file that DIFFERS from the
     repo source, it prints a loud warning and points at the backup that holds
     the newer content, instead of overwriting.
  2. Keep volatile writes out of the tracked file. Claude Code merges
     `settings.json` with `settings.local.json`. Frequent automatic writes
     ("always allow X" from permission prompts) go to `settings.local.json`,
     which we do NOT track. So the tracked `settings.json` stays curated and is
     only touched by a deliberate `/config` (model/theme), which is rare.

  Sharing `model`/`theme` across machines is fine (uniform setup is the goal).
  Sanity check any time: `ls -l ~/.claude/settings.json` should still be a symlink.

### implementation

The dotfiles installer only mapped names to the home root (`~/.name`). Added a
small backward-compatible convention: a `__` in a `*.symlink` filename expands to
`/`, and missing parent dirs are created. So:

    claude/claude__rules__python.md.symlink -> ~/.claude/rules/python.md

Also added a `--dry-run` (`-n`) flag to preview all actions with no side effects.
Verified with the dry-run, then ran the real install: all three resolve and
`settings.json` still parses through the link. Old files backed up to `~/.rcback01`.

Documented in the dotfiles README. To add another machine: clone dotfiles, run
`python3 install.py`.

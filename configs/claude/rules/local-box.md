# Local box rules

Machine-only file (`~/.claude/rules/local-box.md`).
Auto-loaded into every session on this host, for every project.

## What this box is

- Low-secret sandbox: no user-accessible secrets, no browser logins. Reached over SSH + Tailscale from VS Code or via remote controlled claude sessions.
- The box may hold **root-only, revocable service credentials** (e.g. the Cloudflare tunnel JSON at `/etc/cloudflared/<UUID>.json`, root:600). You run unprivileged and cannot read them; never try to work around that, and never copy, echo, or commit anything from `/etc/cloudflared/`. If such a credential is suspected compromised, the response is to rotate it (delete/recreate the tunnel), not to investigate it in place.
- `/etc` service configs are root-owned **copies** deployed from this repo via `scripts/deploy-configs.sh` (a diff is shown at deploy time). Editing the repo file changes nothing live until the user runs the deploy script with sudo - do not expect edits under `configs/` to take effect on their own.
- Permissions run in bypass mode (see `~/.claude/settings.local.json`): tool prompts are skipped, so you have broad latitude to run commands and edit files.

## Trade that latitude for planning

Because prompts are bypassed, raise planning rigor yourself before acting - most of all for changes that affect the whole system rather than a single repo.

### Repo-scoped work

Plan inside the repo: use its `scratch/` or `plans/` folder, creating `plans/` if absent. Do not use the box-level plans folder for repo work.

### System-level work (not tied to a repo)

Examples: installing toolchains/SDKs (flutter, node, rust), global package installs, editing shell rc / PATH / systemd / cron, or anything writing outside a repo.

Before acting, write a short note to
`~/repos/plans/<YYYY-MM-DD>_<NN>_<slug_feature_name>.md`
(`<NN>` is a zero-padded per-day sequence: `00` for the day's first note, then `01`, `02`, ...;
take `max + 1` of that date's existing notes)
covering:

- **Goal** - one line.
- **Decisions** - the choices that are not obvious: which version, install method (apt / snap / official script / asdf / ...), install location, what touches PATH or shell rc.
- **Steps** - the commands you intend to run.
- **Rollback** - how to undo or uninstall.

The note is not optional. Write it for any system-level change before acting,
and "acting" includes presenting `sudo` or other system-modifying commands for me to run -
not only running them yourself. Hand over no such commands until the note exists.
Only an explicit waiver from me skips the note.

Scale the confirmation, not the note:

- Trivial reversible one-liner (`apt list`, a single `which`): no note, just do it.
- Installs, configures globally, or is annoying to undo: write the note AND pause for my approval before acting.
- In between: write the note, then proceed without pausing.

The "unambiguous" allowance governs whether to pause for confirmation, never whether to write the note. For genuinely multi-phase efforts, use the `tracked_development` skill instead of a single note.

## Plans folder

`~/repos/plans/` is box-level scratch for the above - a git repo, committed for history.
Treat old notes as disposable history, not authoritative state.

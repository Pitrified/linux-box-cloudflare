# Workspace Settings

## overview

looking in folder
`/home/pmn/repos/linux-box-cloudflare/workspaces`

we added some 'exclude' patterns in the main vscode workspace

1. do a web search for all the various types of exclude vscode can offer (eg search exclude, files exclude, etc)
1. dive into the whole workspace folders to find other potential large folders to exclude
1. write here what is found
1. update all the workspace settings to exclude those folders

## VS Code exclude settings

VS Code offers three exclude-related settings:

| Setting | Purpose | Effect |
|---------|---------|--------|
| `files.exclude` | Hides files/folders from the Explorer sidebar | Files are invisible in the file tree but still indexed |
| `search.exclude` | Excludes files/folders from Search (Ctrl+Shift+F) | Reduces noise and speeds up searches |
| `files.watcherExclude` | Stops the file watcher from monitoring changes | Reduces CPU/memory usage for large generated dirs |

Additionally:
- `search.exclude` inherits from `files.exclude` by default (can be overridden)
- Glob patterns like `**/.venv/**` match at any depth
- In multi-root workspaces, settings apply to all folders

## Found folders to exclude

Scanned all repos in the workspace. These generated/cache folders exist:

| Pattern | Found in | Purpose |
|---------|----------|---------|
| `**/.venv/**` | Most Python repos | Virtual environments |
| `**/__pycache__/**` | All Python repos | Bytecode cache |
| `**/.ruff_cache/**` | All modern Python repos | Ruff linter cache |
| `**/.pytest_cache/**` | All Python repos with tests | Pytest cache |
| `**/node_modules/**` | fala-comigo-ai-tutor, recipamatic/sv, recipinator/frontend | NPM dependencies |
| `**/cache/**` | kit-hub, laife, llm-core, places-tools, pose-tools, python-project-template, recipamatic, repomgr, tg-central-hub-bot | Data/LLM caches |
| `**/site/**` | (mkdocs build output, if generated) | Static site output |
| `**/.mypy_cache/**` | (if mypy used) | Mypy cache |
| `**/htmlcov/**` | (if coverage used) | Coverage HTML reports |
| `**/build/**` | recipamatic/sv | SvelteKit build output |
| `**/dist/**` | (if built) | Build artifacts |

## Applied settings

All three workspace files updated with consistent exclude patterns.

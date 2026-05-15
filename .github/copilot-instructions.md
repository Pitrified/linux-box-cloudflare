# linux-box-cloudflare - Copilot Instructions

## Project overview

`linux-box-cloudflare` holds configs and tools to manage a personal linux box.
...

... there are different groupings of tools and project types in the linux box ecosystem

## Permanent chat

at the end of all the tasks assigned, always ask a follow up question using the tool #askQuestions to let the user give feedback on the result and guide the next steps

## Style rules

- Never use em dashes (`--` or `---` or Unicode `—`). Use a hyphen `-` or rewrite the sentence.

## Python packages

All modern Python packages in the linux box ecosystem follow the following conventions:

### Running & tooling

```bash
uv run pytest                        # run tests
uv run ruff check .                  # lint (ruff, ALL rules enabled)
uv run pyright                       # type-check (src/ and tests/ only)

uv run mkdocs serve                  # MkDocs local docs server

# webapp dev server
uvicorn <package_name>.webapp.app:app --reload
```

Credentials live at `~/cred/<package_name>/.env` (loaded by `load_env()` in `src/<package_name>/params/load_env.py`).

### Architecture layers

| Layer       | Path                                                 | Role                                                                    |
| ----------- | ---------------------------------------------------- | ----------------------------------------------------------------------- |
| Config      | `src/<package_name>/config/`                         | Pydantic `BaseModelKwargs` models for typed settings                    |
| Params      | `src/<package_name>/params/<package_name>_params.py` | Singleton `<PackageName>Params`; aggregates paths and webapp params     |
| Paths       | `src/<package_name>/params/<package_name>_paths.py`  | `<PackageName>Paths`; env-aware filesystem references                   |
| Env type    | `src/<package_name>/params/env_type.py`              | `EnvStageType` (dev/prod) and `EnvLocationType` (local/render) enums    |
| Webapp      | `src/<package_name>/webapp/`                         | FastAPI app factory, health router, background worker, job queue router |
| Data models | `src/<package_name>/data_models/basemodel_kwargs.py` | `BaseModelKwargs` - Pydantic base with `to_kw()` kwargs flattening      |
| Metaclasses | `src/<package_name>/metaclasses/singleton.py`        | `Singleton` metaclass                                                   |

### Key patterns

**`<PackageName>Params` singleton**  
Access project-wide config via `get_<package_name>_params()` from `src/<package_name>/params/<package_name>_params.py`. It aggregates `<PackageName>Paths` and `WebappParams` and any other params defined by the package. Environment is controlled by `ENV_STAGE_TYPE` (`dev`/`prod`) and `ENV_LOCATION_TYPE` (`local`/`render`) env vars.

```python
from <package_name>.params.<package_name>_params import get_<package_name>_params

params = get_<package_name>_params()
paths = params.paths          # <PackageName>Paths
webapp = params.webapp        # WebappParams
... # others as added over time
```

**`BaseModelKwargs`**  
Extend `BaseModelKwargs` (not plain `BaseModel`) for any config that needs to be forwarded as `**kwargs` to a third-party constructor. `to_kw(exclude_none=True)` flattens a nested `kwargs` dict at the top level.

```python
class SampleConfig(BaseModelKwargs):
    some_int: int
    nested_model: NestedModel
    kwargs: dict = Field(default_factory=dict)

cfg = SampleConfig(some_int=1, nested_model=NestedModel(some_str="hi"), kwargs={"extra": True})
cfg.to_kw(exclude_none=True)  # {"some_int": 1, "nested_model": ..., "extra": True}
```

**Config / Params separation**

- `src/<package_name>/config/` holds Pydantic `BaseModelKwargs` models that define the _shape_ of settings. Use `SecretStr` for every sensitive field. Never read env vars inside config models.
- `src/<package_name>/params/` holds plain classes that load _actual values_ and instantiate config models. Non-secret values are written as Python literals; env-switching is achieved via `match` on `env_type.stage` / `env_type.location`. Secrets are the only values loaded from `os.environ[VAR]` (raises `KeyError` naturally when missing).
- Every Params class accepts `env_type: EnvType | None = None` as its sole constructor argument. `__init__` only stores it and calls `_load_params()`. Loading is orchestrated via `_load_common_params()` then stage/location dispatch.
- Expose the assembled settings through `to_config()` returning the corresponding Pydantic model. Always mask secret fields in `__str__` using `[REDACTED]`.
- See `docs/guides/params_config.md` for the full reference with examples and common mistakes.

The canonical reference implementations are `src/<package_name>/config/sample_config.py` and `src/<package_name>/params/sample_params.py`.

**FastAPI webapp factory**  
`build_app()` in `src/<package_name>/webapp/main.py` builds a minimal FastAPI instance with a health router. Entry point for uvicorn: `<package_name>.webapp.app:app`.

**Env-aware paths**  
`<PackageName>Paths.load_config()` dispatches on `EnvLocationType` (`LOCAL` / `RENDER`) to set environment-specific paths. Common paths (`root_fol`, `cache_fol`, `data_fol`) are always set in `load_common_config_pre()`.

**`Singleton` metaclass**  
Use `metaclass=Singleton` for any class that must have exactly one instance per process (e.g., `<PackageName>Params`). Reset in tests by clearing `Singleton._instances`.

### Documentation

#### Docs folder

Always keep the `docs/` folder of the proper project updated at the end of a task.

- `docs/` holds MkDocs source. `mkdocs.yml` configures the site with the Material theme, mkdocstrings for API reference.
- `docs/guides/` holds narrative guides related to tooling, setup, and project conventions. These are not part of the API reference and should not be written in docstring style.
- `docs/library/` holds description of the core library code. This is not an API reference; write in narrative style with custom headings as needed. Can create subfolders for different domains.
- `docs/reference/` is a virtual folder generated by `mkdocstrings` from docstrings in the source code. Do not write any files here; write docstrings in the source code instead. To reference a file inside this section, link using this structure: [`<some class/function name>`](../../reference/<package_name>/config/sample_config/) which would link to `src/<package_name>/config/sample_config.py`'s API reference page.

#### Docstring style

Use **Google style** throughout. mkdocstrings is configured with `docstring_style: "google"`.

Rules:

- Section labels: `Args:`, `Returns:`, `Raises:`, `Attributes:`, `Note:`, `Warning:`, `See Also:`, `Example:`, `Examples:` - always with a trailing colon, never with an underline.
- `Attributes:` in class docstrings uses two levels of indentation: the attribute name at +4 spaces, its description at +8 spaces.
- Module docstrings are narrative prose. Custom topic headings (e.g., "Pattern rules") are written as plain labelled paragraphs (`Pattern rules:`) - no underline, no RST heading markup.
- `See Also:` lists items as bare lines indented under the section label, not as `*` bullets.

### Logging & exceptions

- Use `loguru` (`from loguru import logger as lg`) for all logging.
- Raise descriptive custom exceptions (e.g., `UnknownEnvLocationError`) rather than bare `ValueError`/`RuntimeError`.

### Testing & scratch space

- Tests live in `tests/` mirroring `src/<package_name>/` structure.
- `scratch_space/` holds numbered exploratory notebooks and scripts. Not part of the package; ruff ignores `ERA001`/`F401`/`T20` there.

### Linting notes

- `ruff.toml` targets Python 3.14 with `select = ["ALL"]`. Key ignores: `COM812`, `D104`, `D203`, `D213`, `D413`, `FIX002`, `RET504`, `TD002`, `TD003`.
- Tests additionally allow `ARG001`, `INP001`, `PLR2004`, `S101`.
- Notebooks (`*.ipynb`) additionally allow `ERA001`, `F401`, `T20`.
- `meta/*` additionally allows `INP001`, `T20`.
- `max-args = 10` (pylint).

### End-of-task verification

After every code change, run the full verification suite before considering the task done:

```bash
uv run pytest && uv run ruff check . && uv run pyright
```

Then update the docs.

# Python tools plan

## Overview

Read repos
* laife (most recent, with clean config integration that i like)
* fastapi-tools
* python-project-template
* linux-box-cloudflare

Extract relevant patterns related to "semi" basic python elements.
Find classes that are redefined in several repos in the same way, and extract them to a common library.
Suggest expansion of the common library with new useful functions and classes.

## Plan

---

### 1. Findings

Deep analysis of `laife`, `fastapi-tools`, and `python-project-template` (`src/` trees only) reveals **8 fully identical files** and **8 near-identical files (>95% match)**. Roughly **15-20% of each repo is copy-paste boilerplate**. The duplication clusters into a tight foundation layer that all three repos share word-for-word.

#### Exact duplicates (3 repos each)

| Class / File | Lines | Pattern |
|---|---|---|
| `BaseModelKwargs` (`data_models/basemodel_kwargs.py`) | 45 | Pydantic base with `to_kw()` kwargs flattening |
| `Singleton` metaclass (`metaclasses/singleton.py`) | 18 | Thread-safe `_instances` dict |
| `EnvStageType`, `EnvLocationType` enums (`params/env_type.py`) | ~70 | `Enum` + `from_env_var()` classmethod, loguru logging |
| `UnknownEnvLocationError`, `UnknownEnvStageError` exceptions | ~30 | Live inside `env_type.py`, same every repo |
| `load_env()` function (`params/load_env.py`) | 15 | `dotenv` loader; only the `"cred/<project-name>/"` path string differs |
| `test_basemodel_kwargs.py` (tests) | 56 | 5 test functions, identical assertions |
| `test_singleton.py` (tests) | 22 | 2 test functions, identical assertions |

#### Near-identical, structurally templated (3 repos each)

| Class | Diff | Detail |
|---|---|---|
| `{Name}Paths` | ~5 lines / 60 total | Module ref + optional extra paths (e.g. `prompts_fol` in laife only) |
| `{Name}Params` (Singleton coordinator) | ~10 lines / 65 total | Sub-module imports differ; core init + `set_env_type()` + `load_config()` identical |

#### Zero duplication (unique per repo)

- **laife**: entity system, LLM services abstraction, mission/brain pipeline, Pygame rendering
- **fastapi-tools**: Google OAuth, `TokenManager`, HTTP exception hierarchy, FastAPI factory, schemas, `get_public_base_url()`
- **python-project-template**: `rename_project.py` scaffolding CLI, full webapp scaffold, agent definitions

---

### 2. What to extract - the common library

Proposed package name: **`pmn-core`** (or `ephem-common` if kept repo-local).

```
pmn_core/
├── data_models/
│   └── basemodel_kwargs.py          # BaseModelKwargs
├── metaclasses/
│   └── singleton.py                 # Singleton metaclass
├── params/
│   ├── env_type.py                  # EnvStageType, EnvLocationType, exceptions
│   ├── load_env.py                  # load_env(project_name: str) - parameterized
│   ├── base_paths.py                # BasePaths - abstract template
│   └── base_params.py               # BaseParams[T] - generic singleton coordinator
└── tests/
    ├── test_basemodel_kwargs.py
    ├── test_singleton.py
    └── test_env_type.py
```

#### Key design to unlock `BasePaths` and `BaseParams`

The `{Name}Paths` and `{Name}Params` classes are 90%+ identical. The only repo-specific parts are:
- the module reference used to anchor `src_fol`
- any extra paths (like `prompts_fol`)
- sub-params instantiated in `load_config()`

This maps cleanly to an abstract base + override hooks pattern. Critically, `load_config()` uses `getattr` dispatch rather than a hardcoded `match/case` - this means `BasePaths` is completely agnostic to what locations a project defines (see section 7 for the full extensibility design):

```python
# pmn_core/params/base_paths.py
import types
from pathlib import Path
from pmn_core.params.env_type import EnvType, UnknownEnvLocationError

class BasePaths:
    def __init__(self, env_type: EnvType, pkg: types.ModuleType) -> None:
        self.env_type = env_type
        self._pkg = pkg
        self.load_config()

    def load_config(self) -> None:
        self.load_common_config_pre()
        # Dynamic dispatch: adding a new location just means
        # implementing load_<location>_config() in the subclass.
        method_name = f"load_{self.env_type.location.value}_config"
        loader = getattr(self, method_name, None)
        if loader is None:
            raise UnknownEnvLocationError(self.env_type.location)
        loader()

    def load_common_config_pre(self) -> None:
        self.src_fol = Path(self._pkg.__file__).parent
        self.root_fol = self.src_fol.parents[1]
        self.cache_fol = self.root_fol / "cache"
        self.data_fol  = self.root_fol / "data"
        self.static_fol = self.root_fol / "static"
        self.templates_fol = self.root_fol / "templates"
```

Each repo's `Paths` class becomes ~10 lines:

```python
# laife/params/laife_paths.py
import laife
from pmn_core.params.base_paths import BasePaths

class LaifePaths(BasePaths):
    def load_common_config_pre(self) -> None:
        super().load_common_config_pre()
        self.prompts_fol = self.src_fol / "prompts"   # laife-specific extra

    def load_local_config(self) -> None:
        pass  # no overrides needed

    def load_render_config(self) -> None:
        pass
```

Similarly `BaseParams` wraps the Singleton boilerplate, and each `{Name}Params` just overrides `load_config()` to attach its domain-specific sub-params.

---

### 3. New additions worth building

Beyond what already exists in some form, the following would be genuinely useful across all current (and future) repos:

#### a. Parameterized `load_env(project_name)`

Right now the project name is hardcoded. One-line fix with big consistency payoff:

```python
# pmn_core/params/load_env.py
def load_env(project_name: str) -> None:
    cred_path = Path.home() / "cred" / project_name / ".env"
    load_dotenv(dotenv_path=cred_path) if cred_path.exists() else ...
```

#### b. Typed env-var reader

A `read_env_var(name, default, cast)` helper that reads, casts, and logs in one shot - replacing the pattern that currently appears ad-hoc inside various `Params` classes:

```python
# pmn_core/params/env_utils.py
def read_env(name: str, default: T, cast: type[T] = str) -> T:
    raw = os.getenv(name, str(default))
    lg.debug(f"EnvVar {name}={raw!r}")
    return cast(raw)
```

#### c. Singleton test helper

Resetting singletons in tests is currently done by directly mutating `Singleton._instances`. Worth providing a proper context manager:

```python
# pmn_core/testing.py
from contextlib import contextmanager
from pmn_core.metaclasses.singleton import Singleton

@contextmanager
def reset_singletons(*classes):
    """Clear and restore Singleton state around a test."""
    saved = {cls: Singleton._instances.pop(cls, None) for cls in classes}
    try:
        yield
    finally:
        for cls, inst in saved.items():
            if inst is not None:
                Singleton._instances[cls] = inst
            else:
                Singleton._instances.pop(cls, None)
```

#### d. `EnvType` dataclass + `EnvVarMixin` (unify the laife vs others divergence)

laife uses a Pydantic `BaseModel` for `EnvType`; fastapi-tools and template use `@dataclass`. The dataclass version is simpler and has no Pydantic overhead here. Standardize on `@dataclass` in the shared lib.

More importantly: ship an `EnvVarMixin` that provides `from_env_var()` as reusable behavior for any project-defined enum. Projects that need custom stages or locations define their own `StrEnum` subclass - no changes to `pmn_core` required. See section 7 for the full design.

#### e. `BaseModelKwargs.to_kw_for(cls)` (optional future addition)

Introspects a target class's `__init__` signature and only emits the keys it actually accepts - removes the need to manually `exclude_none` when some keys would just break the downstream constructor.

#### f. Logging setup helper

All three repos import `from loguru import logger as lg`. A `configure_logging(level, fmt)` helper so each repo gets consistent log format without copy-pasting the sink config.

---

### 4. Options

#### Option A - Standalone PyPI package (recommended for long-term)

- Create `pmn-core/` as an independent repo with its own `pyproject.toml`
- Publish to PyPI (or a private registry / GitHub Packages)
- Each repo pins it in `pyproject.toml`: `pmn-core>=0.1`
- **Pro:** clean versioning, proper changelogs, testable independently
- **Con:** overhead of releases; tiny deps can suffer from version skew

#### Option B - Local uv workspace (easiest to start)

- Create `pmn-core/` as a sibling directory
- Reference it via `uv` workspace path dep: `pmn-core = { path = "../pmn-core" }`
- No publishing needed; shared during active development
- **Pro:** zero friction, changes take effect immediately
- **Con:** all repos must live on the same machine / same workspace checkout

#### Option C - Git subtree

- Keep `pmn-core/` as a subdirectory inside `python-project-template/`
- Pull it into the other repos via `git subtree add --squash`
- **Pro:** self-contained; works without external registry  
- **Con:** subtree merges are ugly; history confusion

#### Option D - Copy-as-is for now, defer extraction

- Accept the duplication while repos are in flux
- Add a `# SHARED: pmn-core candidate` comment to every duplicated file
- Extract only once the API stabilizes
- **Pro:** no migration risk during active development
- **Con:** bugs in shared logic still have to be fixed 3 times

**Recommendation:** Start with **Option B** (uv path dep) immediately. Graduate to **Option A** once the API is stable and there is a third or fourth consumer repo.

---

### 5. Migration path

1. **Create `pmn-core/`** as a uv workspace sibling (Option B)
   - Copy `BaseModelKwargs`, `Singleton`, `env_type.py`, `load_env.py`
   - Parameterize `load_env()` to accept `project_name`
   - Write unit tests (lift existing ones verbatim)
2. **Migrate `fastapi-tools` first** (cleanest, most recent, has best test coverage)
   - Replace `data_models/basemodel_kwargs.py` → import from `pmn_core`
   - Replace `metaclasses/singleton.py` → import from `pmn_core`
   - Replace `params/env_type.py` → import from `pmn_core`
   - Replace `params/load_env.py` → call `pmn_core.params.load_env("fastapi-tools")`
   - Run `uv run pytest && uv run ruff check . && uv run pyright`
3. **Introduce `BasePaths` and `BaseParams`** into `pmn-core`
   - Port `fastapi-tools`'s Paths/Params to the base-class model
   - Verify behavior identical through tests + manual check
4. **Migrate `laife`** (same steps as fastapi-tools + use `BasePaths` override for `prompts_fol`)
5. **Update `python-project-template`** last
   - This one is a template, so the scaffold itself should continue shipping a thin wrapper (2-3 lines) that imports from `pmn-core` - so renamed projects inherit the pattern for free

---

### 6. Total impact estimate

| Stage | Files removed / replaced | Lines delta | Effort |
|---|---|---|---|
| Tier 1 (copy+import swap) | 6 files × 3 repos | -450 duplicated, +6 import lines | 1-2 days |
| Tier 2 (BasePaths / BaseParams) | 2 files × 3 repos | -350 duplicated, +60 in pmn-core | 3-5 days |
| New additions (b-f above) | 0 removed | +~120 in pmn-core | 2-3 days |
| **Total** | **24 files consolidated** | **net -740 lines across repos** | **~1 week** |

---

### 7. Extensible env types

The concern: `EnvStageType` and `EnvLocationType` are not universal. A project might add a `STAGING` stage, a `FLY` location, or drop `RENDER` entirely. Hardcoding these in `pmn_core` would force every project to use the same enum values, defeating the purpose of a shared lib.

#### The problem with shipping concrete enums

Python enums cannot be subclassed when they already have members - so `class MyStageType(DefaultEnvStageType)` to add one value is not valid. The naive approach of forking the enum per project is exactly the duplication we want to avoid.

#### Solution: `EnvVarMixin` + default enums

`pmn_core` ships the **behaviour** (how to read an enum from an env var) as a mixin, and separately ships **default concrete enums** for projects that don't need customization. Projects that do need customization define their own enum with the same mixin - zero changes to the shared lib.

```python
# pmn_core/params/env_type.py
import os
from enum import StrEnum
from typing import Self
from loguru import logger as lg

class EnvVarMixin:
    """Mixin for StrEnum: adds from_env_var() classmethod."""

    @classmethod
    def from_env_var(cls, var_name: str, default: str) -> Self:
        raw = os.getenv(var_name, default)
        lg.debug(f"{var_name}={raw!r}")
        try:
            return cls(raw)  # type: ignore[return-value]
        except ValueError:
            msg = f"Unknown value {raw!r} for {var_name}. Valid: {[e.value for e in cls]}"
            raise UnknownEnvValueError(msg) from None

# Default enums - cover the 95% case; projects import these if their values match.
class DefaultEnvStageType(EnvVarMixin, StrEnum):
    DEV  = "dev"
    PROD = "prod"

class DefaultEnvLocationType(EnvVarMixin, StrEnum):
    LOCAL  = "local"
    RENDER = "render"

# EnvType is generic on the two enum types.
from dataclasses import dataclass
from typing import Generic, TypeVar

StageT    = TypeVar("StageT",    bound=StrEnum)
LocationT = TypeVar("LocationT", bound=StrEnum)

@dataclass
class EnvType(Generic[StageT, LocationT]):
    stage:    StageT
    location: LocationT

    @classmethod
    def from_env_vars(
        cls,
        stage_cls:    type[StageT],
        location_cls: type[LocationT],
        stage_var:    str = "ENV_STAGE_TYPE",
        location_var: str = "ENV_LOCATION_TYPE",
        default_stage:    str = "dev",
        default_location: str = "local",
    ) -> "EnvType[StageT, LocationT]":
        return cls(
            stage=stage_cls.from_env_var(stage_var, default_stage),
            location=location_cls.from_env_var(location_var, default_location),
        )
```

**A project that needs a custom stage** just does this - no edits to `pmn_core`:

```python
# fastapi_tools/params/env_type.py
from pmn_core.params.env_type import EnvVarMixin, DefaultEnvLocationType
from enum import StrEnum

class EnvStageType(EnvVarMixin, StrEnum):  # custom: adds STAGING
    DEV     = "dev"
    STAGING = "staging"
    PROD    = "prod"

# Re-use default location - no need to redefine it.
EnvLocationType = DefaultEnvLocationType
```

**A project that needs no customization** gets everything in one import:

```python
# laife/params/laife_params.py
from pmn_core.params.env_type import DefaultEnvStageType, DefaultEnvLocationType, EnvType

env_type = EnvType.from_env_vars(DefaultEnvStageType, DefaultEnvLocationType)
```

#### Why `getattr` dispatch in `BasePaths` completes the picture

Because `load_config()` now dispatches via `getattr(self, f"load_{location.value}_config")`, adding a `FLY` location to a project is just:
1. Add `FLY = "fly"` to your local `EnvLocationType`
2. Implement `load_fly_config()` in your `Paths` subclass

No changes to `BasePaths`, no changes to `pmn_core`. The base class raises `UnknownEnvLocationError` if the method is missing, giving a clear error at startup rather than a silent wrong-path bug.

#### Impact on the migration plan

- Section 2's `BasePaths` already reflects `getattr` dispatch
- `env_type.py` in `pmn_core` ships `EnvVarMixin` + `DefaultEnvStageType` + `DefaultEnvLocationType` + generic `EnvType`
- Each repo's `params/env_type.py` stays (it's now just 5-10 lines importing + optionally extending the defaults)
- No repo is forced to adopt the defaults - they are opt-in by importing `Default*`

# LLM tools plan

## Overview

Read repos
* laife (most recent, with clean config integration that i like)
* convo-craft
* recipamatic
* recipinator

Extract relevant patterns to interface with a LLM model.
Plan for a general-purpose wrapper that can be used across projects.
Suggest expansion roadmap to include more advanced features that might be commonly needed in LLM-driven projects (eg. prompt templates, structured output parsing, common chains, memory management, tool integration, middleware, rate limiting, logging, monitoring).

---

## Analysis - Repo Findings

### 1. laife (`src/laife/llm_services/`, `src/laife/llm/`)

Most mature and cleanest integration. All patterns below originate here.

**LLM dependency set (LangChain 0.2.x stack):**

```
langchain, langchain-community, langchain-openai, langchain-ollama,
langchain-huggingface, langchain-chroma, langgraph (unused),
sentence-transformers, transformers
```

**Config hierarchy** - `BaseModelKwargs` throughout:

```python
class ChatConfig(BaseModelKwargs):
    model: str
    model_provider: str       # dispatched by langchain's init_chat_model()
    temperature: float = 0.2

    def create_chat_model(self) -> BaseChatModel:
        return init_chat_model(**self.to_kw(exclude_none=True))
```

Concrete subclasses: `ChatOpenAIConfig`, `AzureOpenAIChatConfig`,
`OllamaChatConfig`, `HuggingFaceChatConfig`. Each provider only needs to
override `model`, `model_provider`, and add provider-specific fields (e.g.
`api_key`, `azure_endpoint`, `base_url`).

Same pattern for embeddings: `EmbeddingsConfig` → `OpenAIEmbeddingsConfig`,
`AzureOpenAIEmbeddingsConfig`, `OllamaEmbeddingsConfig`,
`HuggingFaceEmbeddingsConfig`; all call `init_embeddings(**self.to_kw(...))`.

**`StructuredLLMChain[InputT, OutputT]`** - the core reusable primitive:

```python
@dataclass
class StructuredLLMChain[InputT: BaseModelKwargs, OutputT: BaseModel]:
    chat_config: ChatConfig
    prompt_str: str          # raw Jinja2 template string
    input_model: type[InputT]
    output_model: type[OutputT]

    def __post_init__(self) -> None:
        self.prompt_template = ChatPromptTemplate.from_messages(
            [("system", self.prompt_str)], template_format="jinja2"
        )
        # Validate: all input model fields must appear in the template
        missing = frozenset(self.input_model.model_fields) - set(self.prompt_template.input_variables)
        if missing:
            raise MissingPromptVariablesError(missing)
        model = self.chat_config.create_chat_model()
        self.chain = self.prompt_template | model.with_structured_output(self.output_model)

    def invoke(self, chain_input: InputT) -> OutputT: ...
    async def ainvoke(self, chain_input: InputT) -> OutputT: ...
```

InputT must extend `BaseModelKwargs` (field names are prompt variables).
OutputT is a plain Pydantic `BaseModel` (schema enforced by `with_structured_output`).

> **Architecture note - composable runnables (tracked in Roadmap Phase 2):**
> The current design tightly couples prompt + LLM + structured output into one dataclass.
> A cleaner long-term split:
> - `LLMRunnable[InputT]` - a typed LCEL runnable accepting `InputT`, returning a raw `AIMessage`
>   (prompt + chat model only; no structured output). Supports streaming and free-text tasks.
> - `StructuredChain[InputT, OutputT]` - composes `LLMRunnable` with `.with_structured_output(OutputT)`.
> This decoupling lets consumers reuse the prompt+model layer across task types without duplicating
> config wiring, and makes `stream()` / `astream()` a natural addition to `LLMRunnable` in Phase 3.

**Prompt management** - versioned Jinja2 files:

```
src/laife/prompts/<name>/v1.jinja
                         v2.jinja   <- current; never edited
```

`PromptLoader(config).load_prompt()` with `version="auto"` scans for the
highest `vN.jinja` and returns the template string. One-time in-memory cache.

**Vector store** - three-layer abstraction:

- `VectorStoreConfig` (abstract `BaseModelKwargs`) → `ChromaConfig`
- `CChroma(Chroma)` wrapper: auto-deduplicates via SHA-256 hash of content +
  metadata; `add_documents()` skips known IDs.
- `EntityStore` facade: accepts `Vectorable` entities, calls `to_document()` /
  `from_document()`. Filter-aware `search_typed()`.

> **Design note - multi-provider extensibility:** Chroma is the only v1 implementation, but the
> three-layer pattern (`VectorStoreConfig` → provider wrapper → `EntityStore`) is explicitly
> designed for additional backends. Adding Pinecone or Weaviate requires:
> 1. A new `PineconeConfig(VectorStoreConfig)` in `vectorstores/config/pinecone.py`.
> 2. A thin wrapper (if deduplication or retry logic is needed) in `vectorstores/cpinecone.py`.
> 3. `EntityStore` stays unchanged - it depends only on the `add_documents` / `similarity_search`
>    interface, not on the concrete backend.
>
> Gate each backend behind its own optional dependency group:
> `pinecone = ["langchain-pinecone>=0.1", "pinecone-client>=3.0"]`
>
> **Known v1 limitation:** consumers needing a non-Chroma backend must wait for v2, contrib a
> new config module, or wrap their backend manually and pass it to `EntityStore` directly.

**`to_prompt()` convention** - every domain object that feeds an LLM context
exposes a `to_prompt() -> str` method. Chains call `entity.to_prompt()` to
build their input model fields.

---

### 2. convo-craft (`src/convo_craft/llm/`)

Simple, stateless single-turn LLM tasks in a Streamlit app.
LangChain 0.3.1, OpenAI only.

**Config:** standard Pydantic `BaseModel` (not `BaseModelKwargs`), direct
`ChatOpenAI(**config.model_dump())` instantiation.

**Prompt:** inline `ChatPromptTemplate` with `HumanMessagePromptTemplate.from_template()`.
Variables injected via `.invoke({"key": value})`.

**Structured output:** `model.with_structured_output(PydanticModel)` - identical
pattern to laife but built ad-hoc per task, not through a shared chain class.

**No memory, no RAG, no streaming, no async.** Each LLM call is fully stateless.

**Notable samples** in `scratch_space/structured/`:
- Direct OpenAI SDK: `client.beta.chat.completions.parse(response_format=Model)`
- Demonstrates that `with_structured_output` is the LangChain wrapper over the
  same OpenAI structured output API.

---

### 3. recipamatic (`py/src/recipamatic/cook/recipe_core/`)

Single LLM task: convert raw recipe text into a typed Pydantic hierarchy.
LangChain 0.3.12, OpenAI only.

**Config:** plain `BaseModel` with `to_model()` factory returning `ChatOpenAI`.
(Pre-dates `BaseModelKwargs`; same idea, less generic.)

**Chain (LCEL):**

```python
chain = transcriber_prompt | model.with_structured_output(RecipeCore)
result: RecipeCore = chain.invoke({"recipe": text})
```

**Pydantic output model:** 3-level nesting
(`RecipeCore` → `Preparation` → `Ingredient` / `Step`). Field descriptions
guide the LLM schema inference.

---

### 4. recipinator (`backend/be/src/be/data/`)

No active LLM inference. Has a custom `VectorDB(Chroma)` subclass with
SHA-256-based document deduplication - same idea as laife's `CChroma`, built
independently. Sentence-transformers for embeddings (no LLM needed).

---

## Pattern Synthesis

| Capability | laife | convo-craft | recipamatic | recipinator |
|---|---|---|---|---|
| Chat config abstraction | `ChatConfig` + subclasses | ad-hoc `BaseModel` | ad-hoc `BaseModel` | - |
| Embeddings config | `EmbeddingsConfig` + subclasses | - | - | direct |
| Vector store config | `VectorStoreConfig` → Chroma | - | - | custom subclass |
| Generic chain wrapper | `StructuredLLMChain[I,O]` | manual per task | manual per task | - |
| Versioned prompts | `PromptLoader` + Jinja2 | inline strings | inline strings | - |
| `to_prompt()` on objects | yes | - | - | - |
| `Vectorable` protocol | yes | - | - | - |
| Async support | yes (`ainvoke`) | no | no | - |
| Multi-provider | yes (4 providers) | no | no | - |
| Structured output | `with_structured_output()` | same | same (LCEL) | - |

**laife contains the canonical versions of every pattern.** The other repos
are older or simpler takes on the same ideas. The extraction target is laife.

---

## `llm-tools` - Proposed Library

### Rationale

At minimum three projects (laife, convo-craft, recipamatic) contain
near-identical structured-output code. A fourth (recipinator) reinvented
the same deduplication logic for vector stores. Centralising this removes
both duplication and drift while giving smaller projects access to multi-provider
support and async they do not currently have.

### Package name

`llm_tools` (installable as `llm-tools`).

### Scope at v1 (extract existing, validated patterns only)

Everything below has already been proven in laife and partially in the other repos.
No new invention is required for v1.

```
src/llm_tools/
├── data_models/
│   └── basemodel_kwargs.py       # BaseModelKwargs (shared with python-tools eventually)
├── chat/
│   └── config/
│       ├── base.py               # ChatConfig(BaseModelKwargs) + create_chat_model()
│       ├── openai.py             # ChatOpenAIConfig
│       ├── azure_openai.py       # AzureOpenAIChatConfig
│       ├── ollama.py             # OllamaChatConfig
│       ├── huggingface.py        # HuggingFaceChatConfig
│       └── __init__.py
├── embeddings/
│   └── config/
│       ├── base.py               # EmbeddingsConfig(BaseModelKwargs) + create_embeddings()
│       ├── openai.py
│       ├── azure_openai.py
│       ├── ollama.py
│       ├── huggingface.py
│       └── __init__.py
├── vectorstores/
│   ├── config/
│   │   ├── base.py               # VectorStoreConfig (abstract)
│   │   ├── chroma.py             # ChromaConfig
│   │   └── __init__.py
│   ├── cchroma.py                # CChroma (dedup-aware Chroma wrapper)
│   ├── entity_store.py           # EntityStore facade (Vectorable in, Document out)
│   ├── hasher.py                 # SHA-256 document ID
│   └── vectorable.py             # Vectorable protocol
├── chains/
│   └── structured_chain.py       # StructuredLLMChain[InputT, OutputT]
├── prompts/
│   └── prompt_loader.py          # PromptLoader + PromptLoaderConfig
└── exceptions.py                 # MissingPromptVariablesError, NoPromptVersionFoundError
```

### Key design decisions inherited from laife

1. **`BaseModelKwargs` is the base for all config objects.** `to_kw(exclude_none=True)` is the
   single mechanism for passing config to third-party constructors.

2. **Provider dispatch via `model_provider` / `provider` strings** passed to LangChain's
   `init_chat_model()` / `init_embeddings()`. No manual `if provider == "openai"` branching.

3. **Input model field names are authoritative** - `StructuredLLMChain` validates the prompt
   template on construction so mismatches fail early, not at runtime.

4. **Prompts are versioned files** (`v*.jinja`). The library ships `PromptLoader`; prompt
   files themselves live in the consuming project, under a path that project controls.

5. **`Vectorable` is a structural protocol** (`@runtime_checkable`), not an ABC.
   Any entity class can implement it without inheriting from the library.

6. **Both sync and async** are first-class in `StructuredLLMChain` (`invoke` / `ainvoke`).

### Consumers contract

```python
# Minimal: one-shot structured call
from llm_tools.chat.config.openai import ChatOpenAIConfig
from llm_tools.chains.structured_chain import StructuredLLMChain
from pydantic import BaseModel, Field

class RecipeOutput(BaseModel):
    name: str
    ingredients: list[str] = Field(description="List of ingredients")

class RecipeInput(BaseModelKwargs):
    recipe_text: str   # must match {{ recipe_text }} in prompt

chain = StructuredLLMChain(
    chat_config=ChatOpenAIConfig(),
    prompt_str="Extract recipe from: {{ recipe_text }}",
    input_model=RecipeInput,
    output_model=RecipeOutput,
)
result: RecipeOutput = chain.invoke(RecipeInput(recipe_text="Boil pasta..."))
```

```python
# With versioned prompt file
from llm_tools.prompts.prompt_loader import PromptLoader, PromptLoaderConfig

loader = PromptLoader(PromptLoaderConfig(
    base_prompt_fol=paths.prompts_fol,
    prompt_name="transcriber",
    version="auto",
))
chain = StructuredLLMChain(
    chat_config=OllamaChatConfig(model="llama3.2"),
    prompt_str=loader.load_prompt(),
    input_model=RecipeInput,
    output_model=RecipeOutput,
)
```

```python
# With vector store entity persistence
from llm_tools.vectorstores.config.chroma import ChromaConfig
from llm_tools.vectorstores.entity_store import EntityStore

store = EntityStore(ChromaConfig(
    embeddings_config=OpenAIEmbeddingsConfig(),
    persist_directory="/data/vectorstore",
))
store.save(recipe_entity)       # entity implements Vectorable
docs = store.search("pasta")
```

---

## Expansion Roadmap

The items below are not yet present in any repo and should be added
incrementally as actual project needs arise.

### Phase 2 - Conversation history and RAG

**Conversation memory** - a typed `ConversationHistory` accumulating
`HumanMessage` / `AIMessage` pairs, serialisable to/from disk (JSON or
SQLite). `StructuredLLMChain` gains an optional `history` parameter.

**RAG chain** - a `RagChain[InputT, OutputT]` that retrieves context from an
`EntityStore` before calling the LLM. The retrieved documents are injected
into the prompt via a dedicated `{{ context }}` variable.

**Session-scoped stores** - thin wrapper to namespace a `EntityStore` per user
session ID, enabling per-user knowledge bases.

### Phase 3 - Streaming and progressive output

Add `stream()` / `astream()` to `StructuredLLMChain` wrapping LangChain's
streaming API. Partial output as `OutputT` instances via partial Pydantic
validation. Useful for Streamlit (convo-craft pattern) or HTMX server-sent
events (fastapi-tools pattern).

### Phase 4 - Tool calling and agent loop

**Tool definitions** - register Python functions as LangChain tools with
typed input/output. Describe tool schema via Pydantic, consistent with the
`BaseModelKwargs` pattern.

**Agent loop** - a minimal `ReActAgent` (or LangGraph wrapper) that iterates
Thought → Action → Observation until done. laife's `PlayerBrain` / `Mission`
/ `WorldRunner` is the prototype for what a more general agent loop looks like.

**Function routing** - a `ToolRouter` that dispatches parsed `BaseAction`
sub-types to registered handlers, reducing the manual `isinstance` dispatch
pattern visible in laife's action processing.

### Phase 5 - Observability and middleware

**Structured LLM call log** - loguru-based `slog.bind(event=..., model=...,
elapsed=...)` already exists in laife; standardise as a shared decorator /
context manager so all chain invocations emit the same log schema.

**Usage metrics** - Add callbacks to count tokens, calls, errors per model. Emit
*structured metrics to a monitoring backend (e.g. Prometheus).

**LangSmith / OpenTelemetry integration** - optional tracing backend;
gated by a `LANGCHAIN_TRACING_V2` env var so it is zero-cost when disabled.

**Retry and rate limiting middleware** - configurable retry with exponential
backoff (wraps `invoke`/`ainvoke`); per-model concurrency limits for Ollama
and HuggingFace local models. LangChain provides a minimal rate limiter,
we need to build a more robust one that counts tokens.

**Prompt caching** - extend `PromptLoader` to hash template content;
optionally pass through OpenAI prompt caching headers.

### Phase 6 - Model evaluation and testing

**Deterministic test fixtures** - a `FakeChatModel` returning pre-configured
`OutputT` instances from a registry keyed by input hash. Eliminates API calls
in unit tests.

**Structured evals** - a `ChainEval` harness: given `[(InputT, expected OutputT)]`
pairs, run the chain, compute field-level accuracy, and surface a structured
report. Integrates with the `PromptLoader` versioning scheme.

**LangGraph + reasoning agent** - upgrade the `ReActAgent` from Phase 4 to a full
LangGraph state machine with typed, inspectable intermediate steps:

- Nodes: `PlannerNode → ToolCallNode → ObservationNode → ReflectionNode → TerminalNode`.
- All edges gated by a typed `AgentState(BaseModel)` that accumulates the reasoning trace.
- The typed-state approach maps cleanly onto the `BaseModelKwargs` pattern and makes each
  reasoning step available to the `ChainEval` harness above.
- `ReflectionNode` cross-links to the eval harness: it can score its own output against
  expected ground truth and trigger re-planning before emitting a final answer.
- laife's `PlayerBrain` / `Mission` / `WorldRunner` remain the design prototype; the LangGraph
  version generalises the pattern beyond the game domain.

---

## Dependency Strategy

Use optional dependency groups to keep the install surface small:

```toml
[project]
dependencies = [
    "pydantic>=2.0",
    "langchain-core>=0.3",      # abstractions only; no provider
]

[project.optional-dependencies]
openai      = ["langchain-openai>=0.2"]
azure       = ["langchain-openai>=0.2"]
ollama      = ["langchain-ollama>=0.1"]
huggingface = ["langchain-huggingface>=1.0", "sentence-transformers>=3.0"]
chroma      = ["langchain-chroma>=0.1", "chromadb>=0.5"]
all         = ["llm-tools[openai,azure,ollama,huggingface,chroma]"]
```

Projects that only use OpenAI + Chroma pay no cost for Ollama / HuggingFace
wheels. laife would use `llm-tools[all]`; recipamatic / convo-craft would use
`llm-tools[openai]`.

### Local development vs CI install

One source of truth: the consumer's `pyproject.toml` always declares `llm-tools` via a
git-tag pin. Local development overrides the resolved package with a `Makefile` target;
`pyproject.toml` itself never changes between environments.

**Consumer `pyproject.toml` (permanent, committed):**

```toml
[project]
dependencies = [
    "llm-tools[openai] @ git+https://github.com/<org>/llm-tools@v0.1.0",
]
```

Tag every `llm-tools` release (`v0.1.0`, `v0.2.0`, ...). Consumers update their
pin explicitly on each upgrade by editing the `@vX.Y.Z` suffix and re-locking.

**Per-consumer `Makefile` target for local development (copy-paste template):**

```makefile
LLM_TOOLS_PATH ?= ../llm-tools

.PHONY: dev-llm-tools
dev-llm-tools:  ## Swap llm-tools to a local editable install for development
	uv pip install -e "$(LLM_TOOLS_PATH)[all]"
	@echo "llm-tools is now installed from $(LLM_TOOLS_PATH)"
	@echo "Run 'uv sync' to revert to the pinned git version."
```

Usage:

```bash
# From inside the consumer project directory:
make dev-llm-tools                      # uses ../llm-tools
make dev-llm-tools LLM_TOOLS_PATH=~/dev/llm-tools  # custom path
```

Running `uv sync` in the consumer at any time reverts to the pinned git version.
The `uv.lock` file always reflects the git pin; the local editable overlay is
never committed.

**Pitfalls:**

- The editable pip overlay is invisible to `uv lock`. If you run `uv sync` after
  `make dev-llm-tools`, the local install is silently reverted. Add a guard comment
  in the `Makefile` and document in the project `README`.
- Version skew: a breaking change to `BaseModelKwargs` or `StructuredLLMChain` requires
  coordinated updates across all consumers. Mitigate by keeping public `__all__` stable and
  deprecating symbols before removing them (at least one release cycle).
- Developers who forget to run `make dev-llm-tools` after a fresh clone will pick up the
  git-pinned version and may miss local changes - make this the first step in the project
  `CONTRIBUTING.md`.

---

## Sanity Check - Pitfalls and Risks

### 1. Version fragmentation across consumers

Different repos will inevitably pin different versions of `llm-tools`. A bug
fix or new provider in v0.3 means nothing to a consumer still on v0.1. There
is no automatic propagation signal. Mitigations:

- Maintain a `CHANGELOG.md` with explicit "consumers must update X" callouts.
- Add a `llm-tools --check-version` CLI entry point that consumers can call in
  their CI to detect stale pins.
- Consider a [Renovate](https://docs.renovatebot.com/) bot config in each consumer
  repo to auto-create PRs on new `llm-tools` git tags.

### 2. Consumer need to extend library classes

A consumer may need a provider not yet in `llm-tools` (e.g. Anthropic, Groq,
Bedrock) or a custom `ChatConfig` subclass with project-specific defaults.
The plan must document the extension contract:

- **Subclassing is the supported path** for new providers: subclass `ChatConfig` /
  `EmbeddingsConfig` / `VectorStoreConfig` in the consumer project. No fork needed.
- If a consumer-defined subclass is generally useful, they open a PR to upstream it.
- `StructuredLLMChain` accepts `chat_config: ChatConfig` - the type annotation is the
  base class, so any subclass works without changes.
- Risk: if the library uses `isinstance(config, ChatOpenAIConfig)` anywhere instead of
  duck typing, consumer subclasses will break. Enforce duck typing + `to_kw()` throughout.

### 3. `BaseModelKwargs` ownership and duplication

`python-project-template` already ships its own `BaseModelKwargs`. If `llm-tools`
ships a second copy, projects that depend on both get two incompatible base classes.
Options (pick one, commit early):

- **Extract to a separate micro-library** (`python-tools` or `base-models`) and have
  both `llm-tools` and `python-project-template` depend on it. Clean but adds a
  third repo to coordinate.
- **Duplicate and document** - both copies are identical at v1; accept the debt and
  unify later. Simpler short-term, painful when they diverge.
- **Make `llm-tools` a hard dependency of `python-project-template`** - only feasible
  if every project that uses the template also wants LLM features.

### 4. LangChain version drift and resolver conflicts

LangChain's own ecosystem (`langchain-core`, `langchain-openai`, etc.) releases
frequently and sometimes breaks backwards compatibility. If `llm-tools` pins
`langchain-core>=0.3` and a consumer also depends directly on LangChain and pins
tightly, `uv`'s resolver will see conflicting requirements. Mitigations:

- Use wide lower-bound pins in `llm-tools` (`>=X.Y`) with no upper bound; let
  consumers tighten if needed. Never pin exact versions in a library.
- Add a `langchain-compat` CI job in `llm-tools` that tests against the current
  LangChain release weekly, not just on PRs.

### 5. `StructuredLLMChain` constructs a live model at `__post_init__`

Every instantiation creates a real LLM client and potentially an API connection.
This makes testing expensive and slow, and makes it impossible to create a chain
object "speculatively" for configuration purposes. Mitigations:

- Add a `lazy: bool = False` flag; when `True`, defer `create_chat_model()` to
  the first `invoke` call.
- Ship `FakeChatModel` in `llm_tools.testing` from v1, not Phase 6. Without it,
  every consumer that tries to unit-test a chain must mock the model themselves,
  diverging in incompatible ways.

### 6. Prompt variable validation is one-sided

The current validation catches fields in `InputT` that are missing from the prompt
template. It does NOT catch the reverse: template variables with no corresponding
`InputT` field. Those fail at `invoke` time, not at construction. Add a symmetric
check:

```python
extra = frozenset(self.prompt_template.input_variables) - frozenset(self.input_model.model_fields)
if extra:
    raise ExtraPromptVariablesError(extra)
```

### 7. `Vectorable` is informally enforced

`@runtime_checkable` protocols can only verify method existence, not signatures.
A class can pass `isinstance(obj, Vectorable)` even if its `to_document()` returns
the wrong type. This will surface only at `EntityStore.save()` call time. Mitigations:

- Add a `validate_vectorable(obj)` helper that calls `to_document()` on a dummy
  instance and type-checks the result. Call it in EntityStore with a clear error.
- Document that pyright / mypy will catch signature mismatches if consumers use type
  annotations correctly.

### 8. No test isolation story in v1

`FakeChatModel` is planned for Phase 6. Until then, any consumer CI that runs chain
tests needs live API keys. This creates:

- CI cost (API call charges on every PR)
- Flakiness (network failures, rate limits)
- Secret management overhead in every consumer repo

Recommendation: move `FakeChatModel` to v1 scope. It is a small class and pays for
itself immediately across all consumers.

### 9. `EntityStore` couples two orthogonal concerns

`EntityStore` currently ties together deduplication logic (SHA-256) and the
`Vectorable` serialisation protocol. A project that wants the vector store without
the `Vectorable` protocol (e.g. storing raw LangChain `Document` objects) cannot
use `EntityStore` without going around it. Consider splitting:

- `DeduplicatingVectorStore` - wraps any LangChain vector store, adds SHA-256 dedup.
- `EntityStore` - adds `Vectorable` serialisation on top of `DeduplicatingVectorStore`.

### 10. The `to_prompt()` convention is untyped and unenforced

Anything that feeds an LLM context is expected to implement `to_prompt() -> str`,
but there is no protocol or ABC enforcing this. Silent breakage if a class
omits the method and its output is fed to a chain via string interpolation
instead. Minimal fix: add a `Promptable` protocol alongside `Vectorable` and
type-annotate chain input fields that expect it.

---

## Migration Path for Existing Repos

| Repo | Change required |
|---|---|
| **laife** | Replace `src/laife/llm_services/` and `src/laife/llm/prompt_loader.py` + `structured_chain.py` with imports from `llm-tools`. Keep domain-specific files (`player_brain.py`, `mission.py`, etc.). |
| **convo-craft** | Replace `config/chat_openai.py` + per-task boilerplate with `llm-tools` config + `StructuredLLMChain`. |
| **recipamatic** | Replace `langchain_openai_/chat_openai_config.py` + `RecipeCoreTranscriber` internals with `llm-tools`. The Pydantic output models (`RecipeCore`, etc.) stay in recipamatic. |
| **recipinator** | Replace `data/vector_db.py` with `llm-tools.vectorstores.cchroma.CChroma` + `EntityStore`. |
| **tg-central-hub-bot** | Will use `llm-tools` for any future LLM features (currently has none). |

---

## PostgreSQL Vector Store and SQLModel (v1.5 addition)

For projects that already run Postgres, a separate Chroma process is an unnecessary
operational dependency. `pgvector` turns Postgres into a vector store and keeps all
persistence in one place.

**New files in `llm-tools`:**

```
src/llm_tools/vectorstores/
    config/
        postgres.py          # PostgresVectorConfig(VectorStoreConfig)
    cpostgres.py             # dedup-aware wrapper around langchain-postgres PGVector
```

**New optional dependency group:**

```toml
postgres = ["langchain-postgres>=0.0.12", "psycopg[binary]>=3.1", "sqlmodel>=0.0.21"]
```

**`PostgresVectorConfig`** - minimal required fields:

```python
class PostgresVectorConfig(VectorStoreConfig):
    connection_string: SecretStr   # postgresql+psycopg://user:pass@host/db
    collection_name: str
    embeddings_config: EmbeddingsConfig
    pre_delete_collection: bool = False

    def create_store(self) -> PGVector:
        return PGVector(
            embeddings=self.embeddings_config.create_embeddings(),
            collection_name=self.collection_name,
            connection=self.connection_string.get_secret_value(),
            pre_delete_collection=self.pre_delete_collection,
        )
```

`EntityStore` needs no changes - it accepts any `VectorStoreConfig` and calls
`add_documents` / `similarity_search` through the same interface.

**Typed metadata and combined queries:**

PGVector stores metadata as JSONB alongside the vector. This enables combined
vector + SQL filter queries without a second database:

```python
# search with metadata filter (passed through to PGVector's filter kwarg)
results = store.search_typed(
    query="pasta recipe",
    entity_type=RecipeEntity,
    filter={"cuisine": "italian", "serves": {"$gte": 4}},
)
```

For richer SQL access (joins, aggregations, full-text search alongside vectors)
use **SQLModel** to define the same entities as ORM models. The `Vectorable`
protocol and the SQLModel class co-exist on the same entity:

```python
class RecipeEntity(SQLModel, table=True):   # SQLModel ORM
    id: str = Field(primary_key=True)
    name: str
    cuisine: str

    # Vectorable protocol implementation
    def to_document(self) -> Document: ...
    @classmethod
    def from_document(cls, doc: Document) -> "RecipeEntity": ...
    def to_prompt(self) -> str: ...
```

This avoids maintaining two parallel model hierarchies. The same entity is
read/written via both SQLModel queries and `EntityStore` vector search.

**`llm-tools` provides** the `PostgresVectorConfig` and the dedup wrapper.
**The consumer project** owns the SQLModel table definitions and the migration
strategy (Alembic or `SQLModel.metadata.create_all`).

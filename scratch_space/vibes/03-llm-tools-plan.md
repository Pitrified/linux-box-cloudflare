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

UPDATE: we could decouple the prompt from the structured output,
and make `StructuredLLMChain` a standard runnable, typed (not a chain)
Then we have another chain that does the minimal prompt+LLM call.

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

UPDATE: Chroma is just one implementation of the vector store; the library should be designed to allow other providers (Pinecone, Weaviate, etc.) via the same config → wrapper → facade pattern.

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

**LangSmith / OpenTelemetry integration** - optional tracing backend;
gated by a `LANGCHAIN_TRACING_V2` env var so it is zero-cost when disabled.

**Retry and rate limiting middleware** - configurable retry with exponential
backoff (wraps `invoke`/`ainvoke`); per-model concurrency limits for Ollama
and HuggingFace local models.

**Prompt caching** - extend `PromptLoader` to hash template content;
optionally pass through OpenAI prompt caching headers.

### Phase 6 - Model evaluation and testing

**Deterministic test fixtures** - a `FakeChatModel` returning pre-configured
`OutputT` instances from a registry keyed by input hash. Eliminates API calls
in unit tests.

**Structured evals** - a `ChainEval` harness: given `[(InputT, expected OutputT)]`
pairs, run the chain, compute field-level accuracy, and surface a structured
report. Integrates with the `PromptLoader` versioning scheme.

UPDATE: langgraph + reasoning agent

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

---

## Migration Path for Existing Repos

| Repo | Change required |
|---|---|
| **laife** | Replace `src/laife/llm_services/` and `src/laife/llm/prompt_loader.py` + `structured_chain.py` with imports from `llm-tools`. Keep domain-specific files (`player_brain.py`, `mission.py`, etc.). |
| **convo-craft** | Replace `config/chat_openai.py` + per-task boilerplate with `llm-tools` config + `StructuredLLMChain`. |
| **recipamatic** | Replace `langchain_openai_/chat_openai_config.py` + `RecipeCoreTranscriber` internals with `llm-tools`. The Pydantic output models (`RecipeCore`, etc.) stay in recipamatic. |
| **recipinator** | Replace `data/vector_db.py` with `llm-tools.vectorstores.cchroma.CChroma` + `EntityStore`. |
| **tg-central-hub-bot** | Will use `llm-tools` for any future LLM features (currently has none). |

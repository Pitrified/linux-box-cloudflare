# Language core tracking

High-level tracking of language-related projects in the linux-box ecosystem.
Create dedicated tracking documents for sub-tasks with the format `NN-feature-name.md` as needed, increasing prefix.

Core analysis: [00-language-overview.md](./00-language-overview.md)

## Source repos

| Repo | Status | What it provides | Target |
|------|--------|------------------|--------|
| `convo_craft` | existing | Bilingual conversation generation + sentence reconstruction game | Port core logic to unified app |
| `brazilian-bites` | existing | Flashcard/vocab app, false friends, pair matching, weighted selection | Port word model + matching game |
| `fala-comigo-ai-tutor` | existing | AI conversational tutor with corrections | Port tutor chat + topic generation |
| `go-accenter` | existing | Diacritic typing practice, Wiktionary data pipeline | Port to Python as `accenter` |
| `worldly-words` | existing | Multilingual Wordle clone | Port to Python as `wordle-multilingual` |

## Unification phases

### Phase 1 - Shared data layer `[not started]`

Define canonical Pydantic models that all exercise types share. This is the foundation.

- [ ] `Word` model - accented form, normalized form, language, translations, POS, topics, frequency, glosses, examples, false friend metadata
- [ ] `Language` model - code, name, native name, accented chars, normalization map, keyboard layout
- [ ] `UserWordProgress` model - per-user per-word stats (seen/correct/error counts, timestamps), computed weight
- [ ] Accent normalization module - merged maps from go-accenter + worldly-words, multi-language
- [ ] Word ingestion pipeline - Wiktionary JSONL, CSV, LLM generation

Details: [02-shared-data-layer.md](./02-shared-data-layer.md)

### Phase 2 - Exercise framework `[not started]`

Abstract each exercise type into a common interface with shared scoring/progress.

- [ ] Common exercise interface (word/sentence source, interaction model, scoring callback)
- [ ] Sentence reconstruction (from convo_craft)
- [ ] Pair matching (from brazilian-bites)
- [ ] Conversational tutor (from fala-comigo)
- [ ] Diacritic typing (from go-accenter)
- [ ] Wordle guessing (from worldly-words)

Details: [03-exercise-framework.md](./03-exercise-framework.md)

### Phase 3 - LLM services `[not started]`

Consolidate all LLM usage via `llm-core` StructuredLLMChain with versioned Jinja prompts.

- [ ] TranslationChain
- [ ] ConversationGeneratorChain
- [ ] TutorResponseChain
- [ ] TopicSuggestionChain
- [ ] ParagraphSplitterChain

Details: [04-llm-services.md](./04-llm-services.md)

### Phase 4 - Unified webapp `[not started]`

Single FastAPI backend, shared frontend, user accounts, cross-exercise progress.

- [ ] FastAPI app (kit-hub / fastapi-tools patterns)
- [ ] Frontend (HTMX + Jinja2 or SPA)
- [ ] User accounts + aggregated progress
- [ ] Global language selection

Details: [05-unified-webapp.md](./05-unified-webapp.md)

## Sub-task documents

| File | Topic |
|------|-------|
| [02-shared-data-layer.md](./02-shared-data-layer.md) | Word, Language, UserWordProgress models; normalization; ingestion pipeline |
| [03-exercise-framework.md](./03-exercise-framework.md) | Common exercise interface and per-exercise-type design |
| [04-llm-services.md](./04-llm-services.md) | StructuredLLMChain definitions for translation, generation, correction |
| [05-unified-webapp.md](./05-unified-webapp.md) | Webapp architecture, routing, frontend, user accounts |
| [06-word-ingestion.md](./06-word-ingestion.md) | Wiktionary pipeline, CSV import, LLM-generated content |

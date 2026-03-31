# Overview of the language-based projects

## Current repos

We have these existing and planned projects in the language learning / practice space.
They all have a strong focus on Portuguese, but some are designed to be easily adaptable to other languages.

**`convo_craft`** - Generates bilingual conversations via LLM, lets the user translate one side to practice a target language.
Streamlit UI, LangChain / OpenAI backend, structured output with Pydantic.
Very close to `fala-comigo-ai-tutor` which was built with Lovable, but offer different functionality.

**`brazilian-bites`** - Flashcard minimal app. Heavy focus on false friends.
React + shadcn/ui + Tailwind + Supabase. Built with Lovable.
Note that there are some large `.csv` files (not tracked), which are semi-ready to be ingested (there is some upload endpoint to do so).

**`accenter`** _(planned)_ - write words with diacritics to practice accent placement in Portuguese.
It's a refactor of `go-accenter` which did the same in `go` for french.

**`worlde-multilingual`** _(planned)_ - Multilingual Wordle clone, with different languages and word lengths.
It's a refactor of `worldly-words` which was done with lovable.

## Overview

we want to analyze each of the five repos in terms of:

- Functionality: what does the app do, what features does it have, what user needs does it address?
- Internal data models for language-related concepts: what are the main data structures and models used in the app, how do they relate to the functionality? eg words, sentences, conversations, flashcards, etc. Data models for users and authentication are out of scope for this analysis, we want to focus on the language-related data models.
- Tech stack is completely irrelevant, but we can note it for context. We want to port all the functionality to a core stack of python, but this is not the focus of the analysis.

## Functional Analysis

### `convo_craft`

**What it does:** Generates bilingual conversations via LLM and has the user reconstruct one side word by word to practice a target language.

**Features:**

- **Topic generation:** LLM generates a list of conversation topics appropriate for the user's understanding level. Seed topics are provided to avoid duplicates.
- **Conversation generation:** Given a topic, generates a multi-turn dialogue (configurable number of messages and sentences per message) in the target language. A difficulty sample conversation is included as a few-shot example to calibrate the output level.
- **Translation:** Each conversation turn is translated to the user's native language (English) via LLM. The user sees the English translation and must reconstruct the original target-language sentence.
- **Word-level reconstruction game:** The target sentence is split into portions (via LLM paragraph splitting and then a local sentence splitter that merges short words). Portions are shuffled and displayed as clickable buttons. The user must tap them in the correct order to reconstruct the sentence. Wrong guesses are flagged visually; correct ones accumulate into the rebuilt sentence.
- **Conversation progression:** Once a turn is reconstructed, the user advances to the next turn. The conversation is "done" when all turns are completed.

**Data models:**

- `ConversationTurn(role: ConversationRole, content: str)` - a single dialogue line, role is USER or SYSTEM.
- `ConversationGeneratorResult(turns: list[ConversationTurn])` - the full generated dialogue.
- `TopicsPickerResult(topics: list[str])` - a list of topic strings.
- `TranslatorResult(target_text: str)` - a translated text.
- `ParagraphSplitterResult(portions: list[str])` - portions of a paragraph.
- `AppWordGuess(word: str, state: str)` - a word in the shuffled reconstruction, state is `normal`/`correct`/`wrong`/`inactive`.

**Tech stack:** Python, Streamlit, LangChain + OpenAI, Pydantic structured output.

---

### `brazilian-bites`

**What it does:** Flashcard/vocabulary app focused on Brazilian Portuguese, with a strong emphasis on false friends (words that look similar in English/Italian but mean something different).

**Features:**

- **Pair matching game:** 5 Portuguese words are shown on the left, their English translations (shuffled) on the right. The user taps one from each column to match them. Correct matches stay; wrong ones flash red. Progress is tracked per word.
- **Vocabulary review:** Browse words by topic. Words can be sorted alphabetically or shuffled. Each word card shows: Portuguese word, English translation, word type (verb/noun/adjective/expression), frequency level (high/medium/low), false friend warning marker, regional vocabulary marker, notes, example sentences in both languages, and quick links to Google search and Portuguese Wikipedia.
- **Per-user progress tracking:** Anonymous users get a local user ID. Per-word stats are tracked: seen count, correct count, error count, last seen timestamp.
- **Weighted word selection:** Words are selected for practice rounds using a weighting algorithm that considers user progress (errors boost weight, correctly answered words decrease weight). New/unseen words are prioritized.
- **Batch CSV upload:** A Python script for bulk-importing vocabulary from CSV files into Supabase.

**Data models:**

- `Word` - the core vocabulary entity:
  - `portuguese`, `english` - the word pair
  - `word_type` - verb/noun/adjective/expression
  - `topic`, `secondary_topics` - categorization
  - `frequency` - high/medium/low
  - `is_regional`, `region` - regional variant flag
  - `is_false_friend`, `false_friend_language` - EN/IT/both
  - `similarity_score_en`, `similarity_score_it` - numeric similarity to cognates
  - `notes`, `example_pt`, `example_en` - supplementary info
- `UserWordProgress` - per-user per-word stats: `seen_count`, `correct_count`, `error_count`, `last_seen_at`
- `WeightedWord` - extends Word with progress and computed `weight` for selection

**Tech stack:** React + TypeScript, shadcn/ui, Tailwind, Supabase (Postgres + Edge Functions). Built with Lovable.

---

### `fala-comigo-ai-tutor`

**What it does:** An AI-powered conversational Portuguese tutor. The user chats in Portuguese and receives real-time corrections and conversation continuation from an LLM.

**Features:**

- **Chat-based tutoring:** The user types in Portuguese, the AI responds with two parts: a correction/feedback message and a conversation continuation. Both include English translations.
- **Topic-based conversations:** Each session has a conversation topic (e.g., "Cultura e Vida Cotidiana no Brasil"). The user can change the topic mid-session via a dialog that suggests new topics generated by the AI.
- **Topic suggestions:** An LLM endpoint generates 3 creative, diverse conversation topics for Portuguese learners.
- **AI-generated initial messages:** When a topic is selected, the AI generates a warm greeting that introduces the topic and asks an opening question.
- **Translation tool:** A basic bidirectional English-Portuguese translation tool. Currently uses a hardcoded dictionary (not LLM) with a set of common words and quick phrases.
- **Voice recording (scaffold):** A pronunciation practice component where the user records themselves saying a Portuguese sentence. Records audio, allows playback. No transcription/evaluation yet - just the recording UI with canned exercises at various difficulty levels.
- **Dashboard (scaffold):** Shows gamification stats - streak, points, level, weekly progress, lessons completed, achievements. Currently mock data.

**Data models:**

- `Message(id, content, sender, timestamp, translation?, correction?, messageType?)` - a chat message, sender is `user` or `tutor`, messageType is `correction` or `conversation`.
- Tutor response structure (from Supabase edge function): `{ correction: { content, translation }, conversation: { content, translation } }`
- Voice exercise: `{ id, text, translation, difficulty, topic }` - hardcoded pronunciation exercises.

**Tech stack:** React + TypeScript, shadcn/ui, Tailwind, Supabase (Edge Functions calling OpenAI gpt-4o-mini). Built with Lovable.

---

### `go-accenter`

**What it does:** A desktop GUI app for practicing accent/diacritic placement in foreign words. Currently targets French using a Wiktionary-sourced word dataset.

**Features:**

- **Character-by-character typing practice:** A secret word (with accents) is shown as underscores. The user types each character in sequence using a custom on-screen keyboard that includes accented characters. If correct, the character is revealed; if wrong, the key is disabled.
- **Hint system:** Three hint levels: off (just underscores), show unaccented letters, show all real letters.
- **Weighted word selection:** Words are selected via weighted random sampling. Weights account for: error count (boosted heavily), frequency, times seen (unseen words get max priority), and a "useless" flag.
- **Glosses/definitions:** Shows Wiktionary glosses (definitions) as clues for the word.
- **Useless word marking:** A button to permanently mark a word as useless (e.g., proper nouns, obscure terms) so it never appears again.
- **Persistent state:** Word stats (errors, times seen, useless flag) are persisted via GORM (SQLite). Progress survives across sessions.
- **Wiktionary data source:** Words are loaded from JSONL files extracted from kaikki.org Wiktionary dumps. Records include: word, part of speech, senses (glosses, examples, categories, tags, topics), and form-of references.

**Data models:**

- `WikiRecord` - a Wiktionary dictionary entry: `word`, `pos`, `senses[]`, `categories[]`, `form_of[]`
- `Sense` - `glosses[]`, `raw_glosses[]`, `examples[]` (each with `text` and `english`), `categories[]`, `tags[]`, `topics[]`
- `Word` - a utf8 string type with helper methods (Len, Prefix, Suffix, RuneAt)
- `InfoWord` - persistence model: `word`, `errors`, `frequency`, `useless`, `times_seen`, `has_accent`, `weight`
- Diacritics: `AccentedLetters` set, `UnaccentLetterMap` for normalization (French-specific: `âàéèëêïîôœüùûç`)

**Tech stack:** Go, Fyne (desktop GUI), GORM (SQLite), kaikki.org JSONL dataset.

---

### `worldly-words`

**What it does:** A multilingual Wordle clone. Guess a hidden word in a chosen language within a limited number of attempts.

**Features:**

- **Classic Wordle gameplay:** Guess a word letter by letter. After each guess, tiles are colored: green (correct position), yellow (correct letter, wrong position), gray (not in word).
- **Multi-language support:** 5 languages: English, Spanish, French, Italian, Portuguese. Each has a curated word list.
- **Configurable word length:** Choose 4, 5, 6, or 7 letter words. Default is 5 for all languages.
- **Dynamic attempt count:** Max attempts = word length + 1.
- **Accent-aware comparison:** Words are stored with accents preserved (`value`) and a normalized form (`normalized`) for comparison. The user types without accents; comparison is done on normalized forms.
- **On-screen keyboard:** Virtual keyboard with state tracking per letter (correct/misplaced/wrong). Also supports physical keyboard input.
- **Win/lose states:** Clear feedback on game completion showing the answer.

**Data models:**

- `Word(value, normalized, language, length)` - a word entry with accent-preserved and accent-stripped forms.
- `Language(code, name, nativeName, wordLengths, defaultLength)` - language configuration.
- `GameState` - `targetWord`, `guesses[]`, `currentGuess`, `results[]` (arrays of `LetterResult`), `gameStatus`, `maxAttempts`, `letterStates` (keyboard state per letter).
- `LetterResult(letter, state)` - per-letter evaluation result, state is `correct`/`misplaced`/`wrong`/`empty`/`pending`.
- `CHAR_NORMALIZATION_MAP` - explicit accent-to-base character map covering Portuguese, French, Spanish, Italian, German, Polish, Czech accented characters.

**Tech stack:** React + TypeScript, shadcn/ui, Tailwind, Framer Motion. Built with Lovable. All data is client-side (no backend).

---

## Common components

### Shared concepts across repos

**1. Word/vocabulary as a core entity**

All five repos center on "words" but model them differently:

| Repo | Core unit | Key attributes |
|------|-----------|----------------|
| `convo_craft` | `ConversationTurn.content` (sentence) | role, content |
| `brazilian-bites` | `Word` | portuguese, english, word_type, topic, frequency, false_friend flags, examples |
| `fala-comigo` | `Message.content` (free text) | sender, translation, correction, messageType |
| `go-accenter` | `WikiRecord.Word` | glosses, frequency, accented letters, error history |
| `worldly-words` | `Word` | value (accented), normalized, language, length |

A unified word model could merge these: a word with its accented form, normalized form, translations, part of speech, frequency, topic, glosses/definitions, example sentences, and false friend metadata.

**2. Diacritics and accent normalization**

Two repos handle this explicitly:

- `go-accenter`: French-specific `UnaccentLetterMap` for accent stripping and identification
- `worldly-words`: Language-agnostic `CHAR_NORMALIZATION_MAP` covering PT/FR/ES/IT/DE/PL/CZ

A unified normalization module should merge these maps and support all target languages.

**3. Language configuration**

Currently implicit or scattered:

- `convo_craft`: Hardcoded to Brazilian Portuguese (single language option)
- `brazilian-bites`: Portuguese-only, with false friend awareness for EN and IT
- `fala-comigo`: Portuguese-only
- `go-accenter`: French-only (accented letters and dataset are French-specific)
- `worldly-words`: Explicit `Language` model with 5 languages, configurable word lengths

A unified `Language` config would define: code, name, native name, supported features (accented chars, normalization map, available word lists, keyboard layouts).

**4. User progress and spaced repetition**

Three repos track user performance:

- `brazilian-bites`: `UserWordProgress` with seen/correct/error counts, weighted selection
- `go-accenter`: `InfoWord` with errors/frequency/times_seen/useless flag, weighted random selection
- `fala-comigo`: Mock dashboard with streak/points/level (not yet functional)

The weighting algorithms are conceptually similar (boost errors, prioritize unseen, decay with exposure). A shared progress model and selection algorithm would serve all exercise types.

**5. LLM-powered content generation**

Three repos use LLMs:

- `convo_craft`: Topic generation, conversation generation, translation, paragraph splitting (all OpenAI via LangChain)
- `fala-comigo`: Tutor response generation, initial message generation, topic suggestions (OpenAI via Supabase Edge Functions)
- `brazilian-bites`: None (static data)

These could converge on a shared LLM service layer (already available via `llm-core`) with structured chains for: translation, conversation generation, grammar correction, topic suggestion.

**6. Exercise types**

The repos collectively offer five distinct exercise mechanics:

| Exercise | Repo | Mechanic |
|----------|------|----------|
| Word reconstruction | `convo_craft` | Tap shuffled word portions in correct order to rebuild a sentence |
| Pair matching | `brazilian-bites` | Match Portuguese words to English translations |
| Conversational chat | `fala-comigo` | Free-form chat with AI correction |
| Diacritic typing | `go-accenter` | Type accented characters one by one to spell a word |
| Wordle guessing | `worldly-words` | Guess a hidden word with positional feedback |

### Roadmap to unification

**Phase 1 - Shared data layer**

- Define a canonical `Word` model in Python (Pydantic) that covers all use cases: accented form, normalized form, language, translations (multi-language dict), part of speech, topics, frequency, glosses/definitions, example sentences, false friend metadata, accent metadata.
- Define a `Language` model: code, name, native name, accented characters set, normalization map, keyboard layout.
- Define a `UserWordProgress` model: per-user per-word stats with seen/correct/error counts and timestamps. Include a `weight` computed property using a shared selection algorithm.
- Build a word ingestion pipeline that can populate from: Wiktionary JSONL dumps (like go-accenter), CSV files (like brazilian-bites), and LLM generation.

**Phase 2 - Shared exercise framework**

- Abstract each exercise type into a common interface: an exercise has a word/sentence source, a user interaction model, and a scoring/progress callback.
- Port the five exercise mechanics to Python:
  - **Sentence reconstruction** (from convo_craft): given a sentence, split into portions, shuffle, let user reorder.
  - **Pair matching** (from brazilian-bites): given N word pairs, shuffle one side, let user match.
  - **Conversational tutor** (from fala-comigo): LLM chat with correction and continuation.
  - **Diacritic typing** (from go-accenter): given a word, let user type it character by character with accent buttons.
  - **Wordle** (from worldly-words): guess a hidden word with positional feedback.
- All exercises push results to the same `UserWordProgress` model.

**Phase 3 - Shared LLM service**

- Consolidate LLM usage via `llm-core` StructuredLLMChain:
  - `TranslationChain` - translate text between any two languages
  - `ConversationGeneratorChain` - generate conversations for a topic and difficulty
  - `TutorResponseChain` - correct user input and continue conversation
  - `TopicSuggestionChain` - generate practice topics for a language
  - `ParagraphSplitterChain` - split text into meaningful portions for reconstruction
- Templates are versioned Jinja files, not hardcoded strings.

**Phase 4 - Unified webapp**

- Single FastAPI backend serving all exercise types, using the `kit-hub` / `fastapi-tools` patterns.
- Frontend (likely HTMX + Jinja2 or a separate SPA) with a shared layout and navigation between exercise modes.
- User accounts with progress aggregated across all exercise types.
- Language selection as a global setting rather than per-app.

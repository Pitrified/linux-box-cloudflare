# Shared data layer

Foundation models that all exercise types and services build on.

## `Word` model

A unified word entity covering all current use cases.

```
Word
  id: uuid
  text: str                        # canonical form with accents ("ação", "café")
  normalized: str                  # accent-stripped lowercase ("acao", "cafe")
  language: str                    # ISO 639-1 code ("pt", "fr", "es", ...)
  part_of_speech: str | None       # "noun", "verb", "adjective", "expression", ...
  frequency: FrequencyLevel | None # HIGH / MEDIUM / LOW

  # translations - keyed by target language code
  translations: dict[str, str]     # {"en": "action", "it": "azione", ...}

  # categorization
  topics: list[str]                # ["food", "travel", "daily life", ...]

  # definitions / glosses (from Wiktionary or similar)
  glosses: list[Gloss]             # list of sense definitions

  # examples
  examples: list[WordExample]      # example sentences with translations

  # false friend metadata
  false_friends: list[FalseFriend] | None

  # accent metadata (derived, not stored)
  has_accent: bool                 # computed from text vs normalized
  accented_chars: list[str]        # ["ã", "ç"] - the specific accented chars present
```

### Supporting types

```
FrequencyLevel = Literal["high", "medium", "low"]

Gloss
  text: str                        # definition text
  examples: list[GlossExample]     # usage examples from dictionary

GlossExample
  text: str                        # example in target language
  translation: str | None          # English translation

WordExample
  sentence: str                    # example sentence in the word's language
  translation: str | None          # translation to user's language

FalseFriend
  language: str                    # which language it's a false friend with ("en", "it")
  similar_word: str                # the misleading cognate
  similarity_score: float | None   # 0.0-1.0 visual/phonetic similarity
  actual_meaning: str              # what the false friend actually means
```

### Design notes

- `text` + `normalized` pair mirrors worldly-words' `value`/`normalized` and go-accenter's accent handling.
- `translations` as a dict supports brazilian-bites' bilingual pairs and extends to N languages.
- `glosses` captures Wiktionary sense data from go-accenter; optional for vocab that comes from CSV or LLM.
- `false_friends` is a list because a word can be a false friend in multiple languages (brazilian-bites tracks EN and IT).
- `frequency` uses the same three-tier model as brazilian-bites.
- `topics` replaces brazilian-bites' `topic` + `secondary_topics` with a flat list.
- `part_of_speech` unifies brazilian-bites' `word_type` and go-accenter's `pos`.

### What each repo maps to

| Source repo | Source field(s) | Unified field |
|-------------|----------------|---------------|
| brazilian-bites | `portuguese` | `text` |
| brazilian-bites | `english` | `translations["en"]` |
| brazilian-bites | `word_type` | `part_of_speech` |
| brazilian-bites | `topic`, `secondary_topics` | `topics` |
| brazilian-bites | `is_false_friend`, `false_friend_language`, `similarity_score_*` | `false_friends` |
| brazilian-bites | `example_pt`, `example_en` | `examples` |
| go-accenter | `WikiRecord.word` | `text` |
| go-accenter | `WikiRecord.pos` | `part_of_speech` |
| go-accenter | `Sense.glosses` | `glosses` |
| go-accenter | `Sense.examples` | `glosses[].examples` |
| worldly-words | `Word.value` | `text` |
| worldly-words | `Word.normalized` | `normalized` |
| worldly-words | `Word.language` | `language` |

---

## `Language` model

Configuration for each supported language.

```
Language
  code: str                        # ISO 639-1 ("pt", "fr", "es", "en", "it")
  name: str                        # English name ("Portuguese")
  native_name: str                 # native name ("Português")

  # accent / diacritic support
  accented_chars: set[str]         # {"â", "ã", "à", "é", "ê", "í", "ó", "ô", "õ", "ú", "ç"}
  normalization_map: dict[str, str] # {"â": "a", "ã": "a", "ç": "c", ...}

  # wordle config
  word_lengths: list[int]          # [4, 5, 6, 7]
  default_word_length: int         # 5

  # keyboard layout for on-screen keyboards
  keyboard_rows: list[list[str]]   # [["q","w","e",...], ["a","s","d",...], ...]
  accent_keys: list[str]           # extra keys for diacritic input
```

### Source mapping

- `worldly-words` already has an explicit `Language` model with code/name/nativeName/wordLengths/defaultLength.
- `go-accenter` has the `AccentedLetters` set and `UnaccentLetterMap` for French.
- `worldly-words` has `CHAR_NORMALIZATION_MAP` covering PT/FR/ES/IT/DE/PL/CZ.
- Merge all into a single per-language config.

### Initial languages

| Code | Name | Accented chars | Source |
|------|------|----------------|--------|
| `pt` | Portuguese | â ã à é ê í ó ô õ ú ç | brazilian-bites, worldly-words |
| `fr` | French | â à é è ë ê ï î ô œ ü ù û ç | go-accenter, worldly-words |
| `es` | Spanish | á é í ó ú ñ ü | worldly-words |
| `it` | Italian | à è é ì ò ù | worldly-words |
| `en` | English | (none) | worldly-words |

---

## `UserWordProgress` model

Per-user, per-word performance tracking that feeds weighted selection.

```
UserWordProgress
  user_id: str
  word_id: uuid
  seen_count: int = 0
  correct_count: int = 0
  error_count: int = 0
  last_seen_at: datetime | None
  is_useless: bool = False         # user-flagged as irrelevant (from go-accenter)

  # per-exercise breakdown (optional, for detailed analytics)
  exercise_stats: dict[str, ExerciseStats]  # keyed by exercise type

ExerciseStats
  seen_count: int = 0
  correct_count: int = 0
  error_count: int = 0
  last_seen_at: datetime | None
```

### Weighted selection algorithm

Merge the approaches from brazilian-bites and go-accenter:

```
weight = base_weight
  * error_boost(error_count)       # errors increase weight significantly
  * unseen_boost(seen_count)       # never-seen words get max priority
  * frequency_factor(frequency)    # high-frequency words slightly preferred
  * recency_decay(last_seen_at)    # recently seen words get lower weight
  * (0 if is_useless else 1)       # useless words excluded entirely
```

Both repos use similar logic:
- brazilian-bites: `weight = base + error_count * penalty - correct_count * bonus`, new words get max weight
- go-accenter: `weight = (1 + errors*3) * frequency_weight * unseen_multiplier`, useless words get 0

The unified version should be parameterizable per exercise type (some exercises might weight frequency differently).

---

## Accent normalization module

A standalone utility that merges character maps from go-accenter and worldly-words.

```
normalize(text: str) -> str
  """Strip all diacritics, lowercase."""

has_accent(text: str) -> bool
  """Check if text contains any accented character."""

extract_accented_chars(text: str) -> list[str]
  """Return list of accented characters present in text."""

get_normalization_map(language: str) -> dict[str, str]
  """Return accent-to-base map for a specific language."""
```

Implementation: use `unicodedata.normalize("NFD", ...)` + category filtering as the general approach, with per-language overrides for special cases (e.g., `œ` -> `oe` in French, `ñ` -> `n` in Spanish).

---

## Open questions

- Should `Word.id` be a UUID or a composite key of `(text, language)`? UUID is simpler for DB, composite is more natural for dedup.
- Should `translations` be a simple dict or a list of `Translation` objects with metadata (source: "human"/"llm", confidence)?
- How to handle multi-word expressions (brazilian-bites has these as `word_type: "expression"`)? Same `Word` model or a separate `Phrase` model?
- Should `glosses` be per-sense (Wiktionary style) or flattened? Per-sense is richer but more complex.

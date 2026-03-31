# Word ingestion pipeline

How to populate the unified `Word` model from various data sources.

## Data sources

### 1. Wiktionary JSONL dumps (from go-accenter)

**Source:** kaikki.org Wiktionary extracts. JSONL files with one `WikiRecord` per line.

**Coverage:** Full dictionary for a language. Thousands to millions of entries. Very rich metadata (glosses, examples, categories, POS, form-of references).

**Current usage:** go-accenter loads French Wiktionary data, filters to words with accents, uses glosses as hints.

**Ingestion mapping:**

```
WikiRecord -> Word:
  text         = record.word
  normalized   = normalize(record.word)
  language     = (from source file metadata)
  part_of_speech = record.pos
  glosses      = record.senses[].glosses, record.senses[].examples
  has_accent   = computed
  accented_chars = extracted from text
```

**Filtering:** Raw Wiktionary has too many entries. Filter by:
- Only headwords (skip form-of entries unless they point to a good lemma)
- Only common POS: noun, verb, adjective, adverb, expression
- Only words with accents (for diacritic typing exercise)
- Frequency data (if available from a separate frequency list)
- Skip proper nouns, abbreviations, archaic terms

**Missing data:** Wiktionary doesn't have translations in a structured way (glosses are in English but not consistently formatted). Translations may need to be generated via LLM or sourced separately.

**Pipeline:**

1. Download JSONL for target language from kaikki.org
2. Parse each line as `WikiRecord`
3. Filter (POS, accent, form-of, etc.)
4. Map to `Word` model
5. Optionally enrich with LLM translations
6. Bulk insert into DB

---

### 2. CSV vocabulary files (from brazilian-bites)

**Source:** Manually curated CSV files with Portuguese-English word pairs and metadata.

**Coverage:** Small but high-quality. Hundreds of words with rich metadata: topics, frequency, false friend flags, examples.

**Current usage:** brazilian-bites has a Python upload script that pushes CSV rows to Supabase.

**CSV columns (known):**

```
portuguese, english, word_type, topic, secondary_topics,
frequency, is_regional, region, is_false_friend,
false_friend_language, similarity_score_en, similarity_score_it,
notes, example_pt, example_en
```

**Ingestion mapping:**

```
CSV row -> Word:
  text         = row.portuguese
  normalized   = normalize(row.portuguese)
  language     = "pt"
  part_of_speech = row.word_type
  translations = {"en": row.english}
  topics       = [row.topic] + row.secondary_topics.split(",")
  frequency    = row.frequency
  examples     = [WordExample(sentence=row.example_pt, translation=row.example_en)]
  false_friends = build from is_false_friend, false_friend_language, similarity_score_*
```

**Pipeline:**

1. Read CSV file
2. Validate required columns
3. Map each row to `Word` model
4. Handle dedup (same word may appear in multiple CSVs)
5. Bulk upsert into DB

---

### 3. Static word lists (from worldly-words)

**Source:** Curated word lists per language, stored as TypeScript arrays in the frontend.

**Coverage:** Small, focused lists for Wordle gameplay. Words are chosen for being common, recognizable, and of the right length.

**Current format:**

```typescript
export const portugueseWords: Word[] = [
  { value: "amigo", normalized: "amigo", language: "pt", length: 5 },
  { value: "ação", normalized: "acao", language: "pt", length: 4 },
  ...
]
```

**Ingestion mapping:**

```
WordList entry -> Word:
  text         = entry.value
  normalized   = entry.normalized
  language     = entry.language
  # minimal metadata - just the word and its normalized form
```

**Enrichment:** These words are bare. They can be enriched post-ingestion by:
- Looking up translations via `TranslationChain`
- Looking up glosses from Wiktionary data (if already ingested)
- Merging with CSV data (if the same word exists there)

**Pipeline:**

1. Extract word arrays from TypeScript source (or convert to JSON/CSV first)
2. Map to `Word` model (minimal fields)
3. Bulk insert, skipping words that already exist with richer data
4. Queue enrichment jobs for bare entries

---

### 4. LLM-generated vocabulary (new)

**Source:** Generate new vocabulary items on demand via LLM.

**Use case:** Fill gaps when no static data exists for a language/topic combination. Generate themed word sets ("10 Portuguese words about cooking" or "5 French false friends with English").

**Proposed chain:**

```
WordGeneratorInput
  language: str
  topic: str
  num_words: int = 10
  difficulty: str = "intermediate"
  require_accents: bool = False

WordGeneratorOutput
  words: list[GeneratedWord]

GeneratedWord
  text: str
  translation: str                 # English
  part_of_speech: str
  example_sentence: str
  example_translation: str
```

**Quality:** LLM-generated words need validation. Cross-check against Wiktionary or a word frequency list to filter out hallucinations.

**Pipeline:**

1. Call `WordGeneratorChain` with desired params
2. Validate each word exists (frequency list or Wiktionary lookup)
3. Map to `Word` model, mark source as "llm_generated"
4. Insert into DB

---

## Deduplication strategy

Multiple sources may provide the same word. Dedup key is `(normalized, language)`.

When merging:
- Richer metadata wins (CSV with examples > bare word list entry)
- Multiple sources' metadata is merged, not overwritten
- Track provenance: `word.sources = ["wiktionary", "csv", "llm"]`
- Translations from different sources are merged into the `translations` dict

## Frequency data

Word frequency is important for selection weighting but hard to source consistently.

Options:
- Wiktionary sometimes includes frequency categories in `tags`
- External frequency lists (e.g., Hermit Dave's word frequency lists on GitHub, based on OpenSubtitles)
- LLM estimation (ask the model to rate frequency as high/medium/low)
- Manual curation (like brazilian-bites' hand-assigned frequency)

Recommendation: Use external frequency lists as the primary source, with fallback to LLM estimation. Manual curation overrides everything.

## Batch processing

For large Wiktionary dumps, ingestion should be batch-oriented:

1. Download + parse phase (offline, produces intermediate JSON)
2. Filter + map phase (produces `Word` objects)
3. Enrichment phase (LLM calls for missing translations, batched)
4. Load phase (bulk DB insert with upsert)

Intermediate results are cached so steps can be re-run independently.

## Open questions

- Should the ingestion pipeline live in the main app or in a separate CLI tool? CLI tool is cleaner for batch jobs.
- How to handle frequency list sourcing? Some lists have licensing restrictions.
- For Wiktionary, should we ingest all POS forms (conjugated verbs, plurals) or only lemmas? Lemmas are simpler; forms are useful for the diacritic exercise.
- How often to re-ingest Wiktionary data? Monthly? On-demand?

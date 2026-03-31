# Exercise framework

A common interface for all exercise types, with shared scoring and progress tracking.

## Common interface

Every exercise implements this contract:

```
ExerciseType = Literal[
    "sentence_reconstruction",
    "pair_matching",
    "conversational_tutor",
    "diacritic_typing",
    "wordle",
]

ExerciseSession
  exercise_type: ExerciseType
  language: Language
  user_id: str
  words: list[Word]                # the word(s) involved in this round

  start() -> ExerciseRound         # initialize a round
  submit(answer) -> RoundResult    # evaluate a user action
  finish() -> SessionSummary       # wrap up and persist progress

ExerciseRound
  prompt: Any                      # exercise-specific prompt data (varies by type)
  expected: Any                    # the correct answer (for validation)

RoundResult
  correct: bool
  feedback: str | None             # per-type feedback message
  word_results: list[WordResult]   # per-word correct/incorrect for progress tracking

WordResult
  word_id: uuid
  correct: bool

SessionSummary
  total_rounds: int
  correct_rounds: int
  words_practiced: list[uuid]
  duration_seconds: float
```

### Progress callback

After every `submit()`, the framework automatically updates `UserWordProgress` for each word involved. The exercise doesn't need to handle this - it just returns `WordResult` entries.

---

## Exercise type: Sentence reconstruction

**Source:** `convo_craft`

**Mechanic:** Given a sentence in the target language and its English translation, split the sentence into portions, shuffle them, and have the user tap them in correct order.

```
SentenceReconstructionRound
  translation: str                 # English translation (shown to user)
  portions: list[str]              # shuffled portions to reorder
  correct_order: list[str]         # expected order

SentenceReconstructionAnswer
  selected_order: list[str]        # user's chosen order
```

**Word selection:** Needs full sentences, not individual words. Source is LLM-generated conversations. The `Word` model doesn't directly apply here - this exercise operates on `ConversationTurn` objects. However, individual words within the sentence can still be tracked for progress.

**Splitting logic:** convo_craft uses an LLM `ParagraphSplitter` chain followed by a local `SentenceSplitter` that merges short portions (< 3 chars with their neighbor). This two-stage approach should be preserved.

**Scoring:** Currently binary per-portion tap (correct position or not). Could be enhanced with partial credit.

---

## Exercise type: Pair matching

**Source:** `brazilian-bites`

**Mechanic:** Show N words in the target language and N shuffled translations. User matches pairs.

```
PairMatchingRound
  left_words: list[str]            # target language words (in order)
  right_words: list[str]           # translations (shuffled)
  pairs: dict[str, str]            # correct mapping (left -> right)
  n_pairs: int = 5                 # configurable, default 5

PairMatchingAnswer
  selected_pair: tuple[str, str]   # (left_word, right_word) per user tap
```

**Word selection:** Weighted random from `UserWordProgress`. Uses the shared selection algorithm. Words must have translations in the user's native language.

**Scoring:** Per-pair correct/incorrect. The round is complete when all pairs are matched.

**Variants:**
- Word-to-translation (default)
- Word-to-definition (using glosses instead of translations)
- Image-to-word (future, if images are added)

---

## Exercise type: Conversational tutor

**Source:** `fala-comigo-ai-tutor`

**Mechanic:** Free-form chat. User writes in the target language, AI responds with correction + conversation continuation.

```
TutorRound
  topic: str                       # conversation topic
  history: list[TutorMessage]      # conversation so far
  ai_greeting: str                 # initial AI message

TutorMessage
  role: Literal["user", "tutor"]
  content: str                     # target language text
  translation: str | None          # English translation
  correction: str | None           # grammar/vocab correction (tutor only)

TutorAnswer
  user_text: str                   # what the user typed
```

**Word tracking:** This exercise doesn't use pre-selected words. Instead, the LLM correction response can extract which words/phrases the user got wrong, and those are tracked for progress. This is a looser coupling to `UserWordProgress`.

**LLM dependency:** Requires `TutorResponseChain` (correction + continuation) and `TopicSuggestionChain`.

**Scoring:** Not binary per-round. Instead track: messages sent, corrections received, topics completed.

---

## Exercise type: Diacritic typing

**Source:** `go-accenter`

**Mechanic:** A word with accents is hidden. User types character by character using an on-screen keyboard with accent keys. Correct characters are revealed; wrong keys are disabled.

```
DiacriticTypingRound
  word: Word                       # the target word (with accents)
  display: list[str]               # current display state ("_" or revealed chars)
  hint_level: HintLevel            # OFF / SHOW_UNACCENTED / SHOW_ALL
  disabled_keys: set[str]          # keys disabled by wrong guesses
  glosses: list[str]               # definition hints

HintLevel = Literal["off", "show_unaccented", "show_all"]

DiacriticTypingAnswer
  character: str                   # the character the user pressed
  position: int                    # current cursor position
```

**Word selection:** Weighted random, same algorithm as pair matching. Words must have `has_accent == True`.

**Hint system (from go-accenter):**
- `off`: all characters shown as underscores
- `show_unaccented`: non-accented characters revealed, accented ones remain underscores
- `show_all`: all real characters shown (essentially just confirms the word)

**Scoring:** Per-character correct/incorrect. A word is "correct" if completed with zero errors.

**Useless marking:** User can flag a word as useless (sets `UserWordProgress.is_useless = True`), permanently removing it from selection.

---

## Exercise type: Wordle

**Source:** `worldly-words`

**Mechanic:** Guess a hidden word within N attempts. After each guess, letters are colored green/yellow/gray.

```
WordleRound
  target: Word                     # the hidden word
  word_length: int                 # 4-7
  max_attempts: int                # word_length + 1
  guesses: list[str]               # guesses so far
  results: list[list[LetterResult]] # per-guess letter evaluations
  keyboard_state: dict[str, LetterState] # per-letter keyboard coloring

LetterResult
  letter: str
  state: Literal["correct", "misplaced", "wrong", "empty", "pending"]

LetterState = Literal["correct", "misplaced", "wrong", "unused"]

WordleAnswer
  guess: str                       # user's guess (normalized for comparison)
```

**Word selection:** Random from word list filtered by language and word_length. No weighting needed - Wordle picks a fresh random word each game.

**Validation:** Guesses must be valid words in the same language and length. Comparison is done on normalized forms (accent-stripped).

**Scoring:** Binary win/lose. Track: games played, games won, guess distribution (how many attempts to win).

---

## Shared components

### Word selector

Centralized weighted-random word selection used by pair matching, diacritic typing, and sentence reconstruction (for picking which conversations to generate).

```
select_words(
    pool: list[Word],
    progress: dict[uuid, UserWordProgress],
    n: int,
    filters: WordFilter | None = None,
) -> list[Word]
```

`WordFilter` allows exercise-specific constraints: `has_accent=True` for diacritics, `min_length`/`max_length` for wordle, `has_translation=True` for pair matching.

### Progress persister

After each exercise round, automatically update `UserWordProgress` for all involved words. Runs as a callback, not within the exercise logic itself.

### Session analytics

Track per-session: exercise type, language, duration, words practiced, accuracy rate. Feed into the dashboard (currently mock in fala-comigo).

# LLM services

Consolidation of all LLM-powered features via `llm-core` `StructuredLLMChain`.

## Current LLM usage by repo

| Repo | Feature | Current implementation |
|------|---------|----------------------|
| convo_craft | Topic generation | LangChain + OpenAI, Pydantic output |
| convo_craft | Conversation generation | LangChain + OpenAI, configurable turns/sentences |
| convo_craft | Translation | LangChain + OpenAI, single text -> translated text |
| convo_craft | Paragraph splitting | LangChain + OpenAI, text -> portions |
| fala-comigo | Tutor response | Supabase Edge Function -> OpenAI gpt-4o-mini |
| fala-comigo | Topic suggestions | Supabase Edge Function -> OpenAI |
| fala-comigo | Initial greeting | Supabase Edge Function -> OpenAI |
| brazilian-bites | (none) | Static data only |
| go-accenter | (none) | Static Wiktionary data only |
| worldly-words | (none) | Static word lists only |

## Proposed chains

All chains use `llm-core`'s `StructuredLLMChain[InputT, OutputT]` with versioned Jinja prompts.

### 1. TranslationChain

Translate text between any two supported languages.

```
TranslationInput
  text: str
  source_language: str       # ISO 639-1
  target_language: str       # ISO 639-1

TranslationOutput
  translated_text: str
```

**Used by:** Pair matching (generate missing translations), sentence reconstruction (show English to user), tutor chat (show translations alongside corrections).

**Consolidates:** convo_craft's `Translator` chain, fala-comigo's inline translation in tutor responses.

**Prompt notes:**
- Preserve the original register and tone.
- For single words, translate as the most common meaning unless context is provided.
- For sentences, produce natural-sounding translations, not literal word-for-word.

---

### 2. ConversationGeneratorChain

Generate a multi-turn bilingual dialogue for a given topic at a given difficulty.

```
ConversationInput
  topic: str
  language: str
  difficulty_level: str            # "beginner" / "intermediate" / "advanced"
  num_turns: int = 6
  max_sentences_per_turn: int = 3
  sample_conversation: str | None  # few-shot example for calibration

ConversationOutput
  turns: list[ConversationTurn]

ConversationTurn
  role: Literal["user", "system"]
  content: str                     # target language
  translation: str                 # English translation
```

**Used by:** Sentence reconstruction exercise, conversational practice.

**Consolidates:** convo_craft's `ConversationGenerator` chain.

**Prompt notes:**
- The conversation should feel natural, not like a textbook dialogue.
- Include common expressions and idioms appropriate for the difficulty level.
- USER turns should be shorter and simpler than SYSTEM turns.
- Include the translation inline rather than requiring a separate translation call.

---

### 3. TutorResponseChain

Given a conversation history and the user's latest message (in the target language), produce a correction and a conversation continuation.

```
TutorInput
  topic: str
  language: str
  user_message: str
  history: list[TutorMessage]
  difficulty_level: str

TutorOutput
  correction: CorrectionBlock
  conversation: ConversationBlock

CorrectionBlock
  content: str                     # correction feedback in target language
  translation: str                 # English translation of the correction
  errors: list[ErrorDetail]        # structured error extraction

ErrorDetail
  original: str                    # what the user wrote
  corrected: str                   # what it should be
  explanation: str                 # brief grammar/vocab note

ConversationBlock
  content: str                     # conversation continuation in target language
  translation: str                 # English translation
```

**Used by:** Conversational tutor exercise.

**Consolidates:** fala-comigo's Supabase edge function `chat-with-tutor`.

**New addition:** `errors` list for structured error extraction. This enables feeding individual corrected words back into `UserWordProgress` - the user's mistakes become targeted practice items.

**Prompt notes:**
- Be encouraging, not pedantic. Praise correct usage.
- If the user makes no errors, skip the correction block (empty content).
- Ask follow-up questions to keep the conversation going.
- Match the difficulty level in vocabulary and grammar complexity.

---

### 4. TopicSuggestionChain

Generate conversation topic suggestions for a given language and difficulty.

```
TopicSuggestionInput
  language: str
  difficulty_level: str
  num_topics: int = 5
  exclude_topics: list[str] = []   # avoid duplicates

TopicSuggestionOutput
  topics: list[str]
```

**Used by:** Conversational tutor (topic selection), sentence reconstruction (topic-based conversations).

**Consolidates:** convo_craft's `TopicsPicker` chain, fala-comigo's `suggest-topics` edge function.

**Prompt notes:**
- Topics should be diverse: culture, daily life, food, travel, news, hobbies, etc.
- Appropriate for the difficulty level (beginner: concrete daily topics; advanced: abstract discussions).
- Specific enough to sustain a conversation, not overly broad.

---

### 5. ParagraphSplitterChain

Split a sentence or paragraph into meaningful portions for the reconstruction exercise.

```
SplitterInput
  text: str
  language: str

SplitterOutput
  portions: list[str]
```

**Used by:** Sentence reconstruction exercise.

**Consolidates:** convo_craft's `ParagraphSplitter` chain.

**Prompt notes:**
- Split at natural phrase boundaries, not randomly.
- Each portion should be 2-5 words typically.
- Preserve punctuation with the word it belongs to.
- Do not split fixed expressions or compound verbs.

**Post-processing:** After LLM splitting, a local `merge_short_portions()` function merges any portions under 3 characters with their neighbor (from convo_craft's `SentenceSplitter`).

---

### 6. GreetingGeneratorChain (new)

Generate an opening message when a new conversational tutor session starts.

```
GreetingInput
  topic: str
  language: str
  difficulty_level: str

GreetingOutput
  greeting: str                    # target language
  translation: str                 # English
```

**Used by:** Conversational tutor exercise (session start).

**Consolidates:** fala-comigo's `generate-initial-message` edge function.

---

## Prompt versioning

All prompts are stored as versioned Jinja2 templates per the `llm-core` pattern:

```
prompts/
  translation/v1.jinja
  conversation_generator/v1.jinja
  tutor_response/v1.jinja
  topic_suggestion/v1.jinja
  paragraph_splitter/v1.jinja
  greeting_generator/v1.jinja
```

Use `PromptLoader(version="auto")` to pick the latest version. Never edit an existing version; add `v2.jinja`, etc.

## Open questions

- Should the tutor chain return `errors` as structured data, or is free-text correction sufficient? Structured is better for progress tracking but harder for the LLM to produce consistently.
  ANSWER: structured `errors` with `original`, `corrected`, and `explanation` fields. This enables feeding mistakes back into the learning algorithm. LLMs with structured output are good now.
- Do we need a `WordGeneratorChain` that can create vocabulary items (with translations, examples, glosses) on the fly? This could supplement static word lists.
  ANSWER: yes.
- Should translation happen inline (as part of conversation/tutor chains) or always via a dedicated `TranslationChain` call? Inline reduces latency; dedicated is more composable.
  ANSWER: inline for conversation/tutor chains to reduce latency and ensure translations are contextually aligned. Dedicated `TranslationChain` can still be used for on-demand translations elsewhere.

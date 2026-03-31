# Unified webapp

Single FastAPI application serving all exercise types, using kit-hub / fastapi-tools patterns.

## Architecture

```
language-app/
  src/language_app/
    config/                        # Pydantic BaseModelKwargs config models
    params/                        # Singleton params, env-aware paths
    data_models/                   # Word, Language, UserWordProgress
    exercises/                     # Exercise framework + per-type logic
    llm/                           # StructuredLLMChain wrappers
    db/                            # SQLAlchemy ORM, CRUD, Alembic migrations
    ingestion/                     # Wiktionary, CSV, LLM word ingestion
    normalization/                 # Accent normalization utilities
    webapp/
      main.py                      # create_app() factory
      app.py                       # uvicorn entrypoint
      routers/
        exercises.py               # /exercises/* - exercise session endpoints
        words.py                   # /words/* - word browsing/management
        progress.py                # /progress/* - user stats and dashboard
        languages.py               # /languages/* - language config
      services/                    # Business logic layer
      schemas/                     # Pydantic request/response models
      templates/                   # Jinja2 templates
      static/                      # CSS, JS, images
```

## Routing

### Exercise endpoints

```
POST   /exercises/{type}/start     # start a new round (returns prompt)
POST   /exercises/{type}/submit    # submit an answer (returns result)
POST   /exercises/{type}/finish    # end session (returns summary)

GET    /exercises/{type}/config    # get exercise-specific settings (e.g., word length for wordle)
```

Where `{type}` is one of: `sentence-reconstruction`, `pair-matching`, `conversational-tutor`, `diacritic-typing`, `wordle`.

### Word endpoints

```
GET    /words                      # list words with filters (language, topic, frequency, etc.)
GET    /words/{id}                 # single word detail
POST   /words/{id}/useless        # mark as useless
```

### Progress endpoints

```
GET    /progress                   # overall dashboard (all exercises, all languages)
GET    /progress/{language}        # per-language breakdown
GET    /progress/words             # per-word stats with sorting/filtering
```

### Language endpoints

```
GET    /languages                  # list available languages with their config
GET    /languages/{code}           # single language detail
```

## Frontend approach

Two options, to be decided:

### Option A: HTMX + Jinja2 (preferred for consistency with kit-hub)

Server-rendered templates with HTMX for interactivity. Each exercise type has its own template with exercise-specific JS for the interactive parts (drag-and-drop for reconstruction, keyboard for wordle/diacritics, etc.).

Pros: Consistent with kit-hub/fastapi-tools patterns, simpler deployment, no build step.
Cons: Some exercises (wordle tile animations, drag-and-drop) need non-trivial client JS anyway.

### Option B: SPA (React/Svelte)

Separate frontend that consumes the FastAPI API. More natural for game-like interactions.

Pros: Better UX for interactive exercises, reuse existing React components from worldly-words/brazilian-bites.
Cons: Separate build/deploy, diverges from kit-hub patterns.

### Recommendation

Start with HTMX + Jinja2 for the framework, word browsing, progress dashboard. For exercises that need heavy client-side interaction (wordle, diacritics), use vanilla JS or Alpine.js within the Jinja2 templates. This keeps the server-rendered pattern while allowing rich interactions where needed.

## User accounts

Follow the fastapi-tools Google OAuth + session pattern:

- Google OAuth login (from fastapi-tools)
- Session-based auth with secure cookies
- `user_id` from Google profile links to `UserWordProgress` records
- Anonymous mode: generate a local UUID, store in cookie. Progress is device-local but still persisted server-side.

## Global settings

Per-user preferences stored in session or DB:

```
UserPreferences
  target_language: str = "pt"      # the language being learned
  native_language: str = "en"      # the user's language for translations
  difficulty_level: str = "intermediate"
  preferred_exercises: list[str]   # exercise types the user likes
```

Language selection is global (set once, affects all exercises) rather than per-exercise.

## Database

SQLAlchemy ORM models, Alembic migrations. Tables:

```
words                              # Word model
languages                          # Language config (could also be static)
user_word_progress                 # UserWordProgress
user_preferences                   # UserPreferences
exercise_sessions                  # Session logs for analytics
```

The DB schema follows the data layer models from 02-shared-data-layer.md.

## Deployment

Render (following kit-hub/media-downloader patterns):
- Single web service running uvicorn
- PostgreSQL database (Render managed)
- Environment variables via Render dashboard
- `render.yaml` for infrastructure-as-code

## Open questions

- Should exercise state (current round, guesses so far) be stored server-side (in session/Redis) or client-side (in JS state sent with each request)? Server-side prevents cheating; client-side is simpler.
- How to handle the wordle word list validation (checking if a guess is a valid word)? Needs a fast lookup, probably an in-memory set loaded at startup.
- Should there be a "daily challenge" mode (like real Wordle) where all users get the same word? Adds social/competitive element.

# Plan: Set up elicitincon-webapp and create project CLAUDE.md

## Context
Setting up a cloned AI safety research webapp for local development and writing a comprehensive `.claude/CLAUDE.md` so future sessions have full project context. Dependencies already installed (`bun install` completed).

## What I learned about the codebase

**App purpose**: Red-team/blue-team experiment for AI safety — tests whether humans can detect AI sandbagging (deliberately wrong answers) and elicit correct answers through conversation.

**Architecture**:
- **Frontend**: React 18 + Vite + React Router (SPA)
- **Backend**: Netlify Functions (serverless) — `chat.js` (OpenAI proxy) + `questions.js` (mock data)
- **Data persistence**: Airtable API (sessions, demographics, responses)
- **LLM**: OpenAI GPT-4.1 (configurable in `src/config/config.js`)
- **Session**: `sessionStorage` (browser) + Airtable records

**Two games**:
1. **Detection Game**: 10 turns × 10 MCQs with pre-generated model responses across epochs. User guesses if model is normal or sandbagging.
2. **Elicitation Game**: User chats with an AI that starts with incorrect answers. Controlled by system prompts (`sp=1` default, `sp=2` adversarial).

**Data sources** (hardcoded, self-contained — no .eval pipeline):
- `src/data/elicitation_data.json` — WMDP-bio MCQs (122 lines)
- `src/data/detectionGameTurns.js` — 5784 lines, 10 turns of pre-generated model responses (generated 2025-07-07, generation script not in this repo)
- `src/data/dataConversion.js` — converts JSON → app format

**Relationship to sandbagging-detection project**: The sibling project at `~/projects/sandbagging-detection/code/` has a separate Next.js webapp (`web/`) with a proper `.eval` → Supabase pipeline (`src/annotation/prepare_study.py`). This elicitincon-webapp is the older/simpler version with static data — no `.eval` file dependency.

**Mock mode**: `VITE_USE_MOCK_DATA=true` — frontend uses local mock data + mock chat (no API calls). Chat falls back to mock if OpenAI key missing.

## Steps

### 1. Create `.env` ✅ (already done: bun install completed)
Copy `.env.example` → `.env` with `VITE_USE_MOCK_DATA=true`.

### 2. Fix: Extend mock flag to bypass all Airtable calls
**Problem**: `VITE_USE_MOCK_DATA` only gates the chat endpoint. `createSession`, `submitDemographics`, `submitResponse`, `completeSession` always call Airtable → 404 errors without credentials.

**Fix in `src/utils/api.js`**: Hoist `USE_MOCK_DATA` to module scope. Add mock check at the top of each Airtable-backed method.

```js
// At top of file (module scope, replaces the per-method check in sendChatMessage):
const USE_MOCK_DATA = import.meta.env.VITE_USE_MOCK_DATA === 'true';

export const api = {
  createSession: (sessionId, gameType, isDemo = false) => {
    if (USE_MOCK_DATA) {
      console.log('[MOCK] createSession:', sessionId, gameType);
      return Promise.resolve({ success: true, recordId: `mock_${sessionId}` });
    }
    return airtableApi.createSession({ sessionId, gameType, isDemo });
  },

  submitDemographics: (sessionId, demographics) => {
    if (USE_MOCK_DATA) {
      console.log('[MOCK] submitDemographics:', sessionId);
      return Promise.resolve({ success: true });
    }
    return airtableApi.submitDemographics(sessionId, demographics);
  },

  // getQuestionSet, getQuestion, getQuestions — already use mockApiCall, unchanged

  sendChatMessage: async (...) => {
    if (USE_MOCK_DATA) { ... }  // already exists, just uses hoisted const now
  },

  submitResponse: (sessionId, gameType, response) => {
    if (USE_MOCK_DATA) {
      console.log('[MOCK] submitResponse:', sessionId, gameType);
      return Promise.resolve({ success: true });
    }
    // existing branching logic for detection vs elicitation
    ...
  },

  completeSession: async (sessionId, recordId = null) => {
    if (USE_MOCK_DATA) {
      console.log('[MOCK] completeSession:', sessionId);
      return { success: true };
    }
    return airtableApi.completeSession(sessionId, recordId);
  }
};
```

**Note**: `session.js` needs no changes — the mock `recordId: 'mock_<uuid>'` flows through naturally and `completeSession` will hit the mock path anyway.

**File**: `src/utils/api.js` (lines 180-262)

### 3. Start dev server and verify
```bash
bun run dev
```
Verify full flow works: Landing → Demographics → Game → ThankYou (no Airtable errors).

### 4. Create `.claude/CLAUDE.md`
Write comprehensive project CLAUDE.md covering:

```
# Inconsistency Elicitation Webapp

## Quick Start
cp .env.example .env   # VITE_USE_MOCK_DATA=true is already set
bun install
bun run dev
# Open http://localhost:5173/?skip=true&game=detection

## Overview
AI safety research webapp: red-team/blue-team experiment testing whether humans
can detect and elicit correct answers from sandbagging AI models.

## Architecture
- Frontend: React 18 + Vite SPA with React Router
- Backend: Netlify Functions (serverless, production only)
- Data: Airtable (persistence, production only) + hardcoded question data
- LLM: OpenAI GPT-4.1 via direct API calls (production only)

## Mock Mode (VITE_USE_MOCK_DATA=true)
When enabled (required for local dev without API keys):
- All Airtable calls (sessions, demographics, responses) return { success: true } stubs
- Chat responses use hardcoded mock logic in api.js (deliberate wrong answers)
- Question data always comes from src/data/ (hardcoded regardless of mock flag)
- Session recordIds prefixed with 'mock_'
- Mock calls logged to console as [MOCK] for visibility

## Key Files
src/
├── App.jsx              # Routes, ProtectedRoute, SkipHandler
├── components/
│   ├── Landing.jsx      # Consent + game assignment
│   ├── Demographics.jsx # Pre-game survey
│   ├── DetectionGame.jsx/css  # Detection game UI
│   ├── ElicitationGame.jsx/css # Chat-based elicitation game
│   ├── SkipHandler.jsx  # Handles ?skip=true for testing
│   └── ThankYou.jsx     # Completion screen
├── config/
│   └── config.js        # OpenAI model config (model, temp, maxTokens)
├── data/
│   ├── elicitation_data.json   # WMDP-bio MCQs (source data)
│   ├── dataConversion.js       # JSON → app format converter
│   └── detectionGameTurns.js   # 10 turns × 10 Qs with model responses
├── utils/
│   ├── api.js           # Main API layer (mock + real endpoints)
│   ├── airtableApi.js   # Airtable CRUD for sessions/responses
│   ├── session.js       # sessionStorage management
│   └── systemPrompts.js # Elicitation system prompts (sp=1, sp=2)
netlify/
├── functions/
│   ├── chat.js          # OpenAI proxy (production)
│   └── questions.js     # Question data endpoint (production)

## Dev Commands
bun install              # Install deps
bun run dev              # Start dev server (Vite)
bun run build            # Production build → dist/
bun run preview          # Preview production build
bun run lint             # ESLint

## Environment Variables
VITE_USE_MOCK_DATA=true    # Mock ALL external APIs (chat + Airtable). Required for local dev.
VITE_OPENAI_API_KEY=...    # OpenAI API key (elicitation chat, production only)
VITE_AIRTABLE_API_KEY=...  # Airtable token (data persistence, production only)
VITE_AIRTABLE_BASE_ID=...  # Airtable base ID (production only)
VITE_API_URL=/api          # API base URL (default: /api)
OPENAI_API_KEY=...         # Server-side OpenAI key (Netlify functions, production only)

## URL Parameters (for testing)
?skip=true       # Skip landing + demographics → go straight to game
?demo=true       # Demo mode (shorter sessions)
?game=detection  # Force detection game
?game=elicitation # Force elicitation game
?sp=1            # System prompt 1 (default: guided incorrect → correct)
?sp=2            # System prompt 2 (adversarial sandbagging)

## Data Flow
1. Landing → consent → random game assignment (or ?game= override)
2. Demographics survey → stored in Airtable
3. Game play:
   - Detection: pre-loaded turns from detectionGameTurns.js
   - Elicitation: live chat via OpenAI API (or mock fallback)
4. Responses → Airtable
5. Session completion → ThankYou

## Related Projects
- ~/projects/sandbagging-detection/code/ — Main research codebase with Inspect AI
  evals, .eval files, and a separate Next.js annotation webapp (web/) using Supabase.
  This elicitincon-webapp is the older/simpler version with static hardcoded data.
- The detectionGameTurns.js data was generated 2025-07-07 (script not in this repo).

## Conventions
- Vanilla CSS (no CSS-in-JS, no Tailwind)
- sessionStorage for client-side session state
- Graceful degradation: Airtable/OpenAI failures don't block UX
- All env vars prefixed VITE_ for client-side access
- No TypeScript (plain JSX)
- No test framework configured
```

### 4. Commit the new files
Stage `.claude/CLAUDE.md` and `.env.example` changes (if any), commit.

## Verification
1. `bun run build` succeeds (syntax check)
2. `bun run dev` starts without errors
3. Open browser, check console for `[MOCK]` logs (confirms mock mode active)
4. Full flow: Landing → Demographics → Detection Game → ThankYou (no Airtable 404s)
5. `?skip=true&game=detection` — loads detection game directly
6. `?skip=true&game=elicitation` — loads elicitation game with mock chat
7. Browser console: no Airtable errors, only `[MOCK]` logs
8. `.claude/CLAUDE.md` exists at correct path

# Plan: Fix Missing Models and Framework Display Issues

## Problem Statement

**Issue 1**: GPT-5.2 and Gemini 3 Pro model card files exist in `data/model_cards/` but don't appear in the leaderboard results (`results/scores.json`). Only 5 models currently show: claude-opus-4-5, deepseek-r1, gemini-2-5-pro, gpt-4o, llama-3-1-405b.

**Issue 2**: Methodology page only shows 1 framework (EU AI Act) instead of all 3 frameworks (EU AI Act, STREAM ChemBio, Lab Safety Commitments).

## Root Causes Identified

### Issue 1: GPT-5.2 - Pipeline Never Re-Run
**Status**: ✅ File is valid and ready
- File exists: `data/model_cards/gpt-5-2.md` (1,332 lines, 48KB, valid markdown)
- Content legitimate: "Update to GPT-5 System Card: GPT-5.2"
- **Problem**: Pipeline was never re-run after file was downloaded
- **Fix**: Simply re-run the pipeline

### Issue 2: Gemini 3 Pro - Incorrect URL (Wrong Path)
**Status**: ❌ File is invalid XML error response due to wrong path
- File exists: `data/model_cards/gemini-3-pro-temp.pdf` (207 bytes)
- Content: XML error message from Google Cloud Storage
```xml
<Error>
  <Code>NoSuchKey</Code>
  <Message>The specified key does not exist.</Message>
  <Details>No such object: deepmind-media/gemini/gemini_3_pro_report.pdf</Details>
</Error>
```
- **Wrong URL** (in script): `https://storage.googleapis.com/deepmind-media/gemini/gemini_3_pro_report.pdf`
- **Correct URL** (user provided): `https://storage.googleapis.com/deepmind-media/Model-Cards/Gemini-3-Pro-Model-Card.pdf`
- **Problem**: Script has wrong path (`gemini/` vs `Model-Cards/`)
- **Fix**: Update URL in download script and re-download

### Issue 3: Methodology Page - Framework Cards Not Rendering
**Status**: ❌ Only 1 of 3 framework cards displays (EU AI Act)
- **Location**: `app/page_methodology.py` lines 148-186
- All 3 framework cards exist in HTML:
  - EU AI Act Code of Practice (lines 149-158) ✅ Renders
  - STREAM ChemBio (lines 160-169) ❌ Doesn't render
  - Lab Safety Commitments (lines 171-184) ❌ Doesn't render
- **Root cause**: Same as grid component - `st.markdown()` with `unsafe_allow_html=True` has limitations rendering complex HTML/CSS
- **Fix**: Use `st.components.v1.html()` to render in iframe (same fix as grid component)

### Technical Context: Pipeline Design
- `src/ingest.py:28` uses `glob("*.md")` - only processes markdown files by design
- PDF files are converted to markdown during download phase (`scripts/download_model_cards.py`)
- The invalid `gemini-3-pro-temp.pdf` wouldn't be processed even if it were valid

## Implementation Plan

### Step 1: Re-run Pipeline for GPT-5.2
**Action**: Execute the pipeline to process the existing `gpt-5-2.md` file

```bash
uv run python scripts/run_pipeline.py
```

**Expected outcome**:
- GPT-5.2 added to `results/scores.json`
- GPT-5.2 appears in leaderboard with scores
- 6 models total in results

**Files affected**:
- `results/scores.json` (updated with GPT-5.2 entry)
- `results/leaderboard.csv` (updated with GPT-5.2 row)

### Step 2: Fix Gemini 3 Pro URL and Download
**Action**: Update download script with correct URL and re-download

**Current URL (wrong)**:
```
https://storage.googleapis.com/deepmind-media/gemini/gemini_3_pro_report.pdf
```

**Correct URL** (user provided):
```
https://storage.googleapis.com/deepmind-media/Model-Cards/Gemini-3-Pro-Model-Card.pdf
```

**Implementation**:
1. Update `scripts/download_model_cards.py` MODEL_CARDS dict with correct URL
2. Delete invalid temp file: `rm data/model_cards/gemini-3-pro-temp.pdf`
3. Re-run download script: `uv run python scripts/download_model_cards.py`
4. Verify gemini-3-pro.md file created successfully
5. Re-run pipeline (same as Step 1) to process both GPT-5.2 and Gemini 3 Pro

### Step 3: Fix Methodology Page Framework Rendering
**Action**: Use `st.components.v1.html()` to properly render all 3 framework cards

**File**: `app/page_methodology.py`

**Problem**: Lines 53-188 use `st.markdown()` which doesn't properly render all framework cards

**Solution**: Replace `st.markdown()` with `st.components.v1.html()`

**Changes needed**:
1. Import `streamlit.components.v1 as components` at top
2. Replace lines 53-188:
   ```python
   # Before
   st.markdown("""<style>...framework cards...</style>""", unsafe_allow_html=True)

   # After
   components.html("""<style>...framework cards...</style>""", height=500, scrolling=False)
   ```

**Expected outcome**: All 3 framework cards render (EU AI Act, STREAM ChemBio, Lab Safety)

## Critical Files

### To Execute:
- `scripts/download_model_cards.py` - Download Gemini 3 Pro with corrected URL
- `scripts/run_pipeline.py` - Re-run to process GPT-5.2 and Gemini 3 Pro

### To Modify:
- `scripts/download_model_cards.py` - Fix Gemini 3 Pro URL (line with MODEL_CARDS dict)
- `app/page_methodology.py` - Replace st.markdown with st.components.v1.html for frameworks

### To Delete:
- `data/model_cards/gemini-3-pro-temp.pdf` - Invalid XML error file

### Results Files (auto-generated):
- `results/scores.json` - Will include GPT-5.2 and Gemini 3 Pro after pipeline run
- `results/leaderboard.csv` - Will include GPT-5.2 and Gemini 3 Pro after pipeline run

## Verification Steps

### After Step 1 (Download Gemini 3 Pro):
```bash
# Check Gemini 3 Pro downloaded successfully
ls -lh data/model_cards/gemini-3-pro.md  # Should exist

# Verify it's a valid markdown file
head -5 data/model_cards/gemini-3-pro.md  # Should show model card content
```

### After Step 2 (Re-run Pipeline):
```bash
# Check both models in results
python3 -c "import json; data = json.load(open('results/scores.json')); print([m['model_name'] for m in data])"

# Expected output should include: 'gpt-5-2' and 'gemini-3-pro'
# Total: 7 models
```

### After Step 3 (Fix Methodology Page):
```bash
# Launch Streamlit app
streamlit run run_app.py

# Navigate to Methodology page
# Scroll to "Frameworks & Standards" section
# Verify all 3 cards visible:
#   1. EU AI Act Code of Practice (amber background)
#   2. STREAM ChemBio (cyan background)
#   3. Lab Safety Commitments (green background)
```

### End-to-End Test:
```bash
# Leaderboard page: Verify GPT-5.2 and Gemini 3 Pro appear in grid and table
# Methodology page: Verify all 3 frameworks display with proper styling
# Click framework links to verify they work
```

## Success Criteria

- [x] Root causes identified for all issues (models + frameworks)
- [ ] Gemini 3 Pro URL corrected in download script
- [ ] Gemini 3 Pro downloaded successfully as `.md` file
- [ ] Invalid `gemini-3-pro-temp.pdf` file removed
- [ ] GPT-5.2 and Gemini 3 Pro appear in `results/scores.json` with compliance scores
- [ ] Both models display in leaderboard grid and table
- [ ] All 3 framework cards render on Methodology page (EU AI Act, STREAM, Lab Safety)
- [ ] Framework cards properly styled with distinct colors
- [ ] No errors when running pipeline or viewing app
- [ ] Total of 7 models in results

---

**Ready for implementation**: All root causes identified, correct URL obtained from user, plan complete.

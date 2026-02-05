# Plan: Extract All Test Cases for 16 Hack2Hire Questions

## Objective
Extract complete test cases (Cases 1-5+) for all 16 questions and save to `test_cases.json` files.

## Current State
- ✅ 16 README.md files exist with problem descriptions
- ✅ `problems/01-worker-management/q1-base/test_cases.json` has 5 cases
- ❌ 15 other questions need `test_cases.json` files

## Approach: Browser Automation

**Curl blocked**: `hack2hire.com` not in sandbox allowed hosts.
**Browser available**: 4 tabs still connected to hack2hire.

### Current Tab State
| Tab ID | Problem | Current Question |
|--------|---------|------------------|
| 375965590 | Banking | Q4 |
| 375965591 | Worker | Q4 |
| 375965592 | Cloud | Q3/Q4 |
| 375965593 | In-memory DB | Q3/Q4 |

### Extraction Script (JavaScript)
```javascript
async function collectAllTestCases() {
  const results = [];
  const allDivs = Array.from(document.querySelectorAll('div'));
  for (let i = 1; i <= 10; i++) {
    const btn = allDivs.find(el => el.innerText === `Case ${i}` && el.offsetParent !== null);
    if (btn) {
      btn.click();
      await new Promise(r => setTimeout(r, 150));
      const allText = document.body.innerText;
      const inputMatch = allText.match(/Input\n([\s\S]*?)(?=Output)/);
      const expectedMatch = allText.match(/Expected\n([\s\S]*?)(?=\n[A-Z]|\nClaude|$)/);
      results.push({
        case: i,
        input: inputMatch ? inputMatch[1].trim() : 'not found',
        expected: expectedMatch ? expectedMatch[1].trim().split('\n')[0] : 'not found'
      });
    }
  }
  return results;
}
collectAllTestCases().then(r => window._testCases = r);
```

## Execution Steps

### Step 1: Extract Current Question Test Cases (Q4s)
Run extraction script on all 4 tabs (currently on Q4).

### Step 2: Navigate to Q1 and Extract
Click sidebar "1" on all tabs → extract test cases.

### Step 3: Navigate to Q2 and Extract
Click sidebar "2" on all tabs → extract test cases.

### Step 4: Navigate to Q3 and Extract
Click sidebar "3" on all tabs → extract test cases.

### Step 5: Save Files
For each of 16 questions, create:
```
problems/<problem>/q<N>-<type>/test_cases.json
```

## Files to Create
| Problem | Q1 | Q2 | Q3 | Q4 |
|---------|----|----|----|----|
| 01-worker-management | ✅ exists | ❌ | ❌ | ❌ |
| 02-cloud-storage | ❌ | ❌ | ❌ | ❌ |
| 03-in-memory-database | ❌ | ❌ | ❌ | ❌ |
| 04-banking-system | ❌ | ❌ | ❌ | ❌ |

**Total: 15 files to create**

## JSON Format
```json
{
  "test_cases": [
    {
      "case": 1,
      "input": "[\"ClassName\", \"method1\", ...]\n[[args], ...]",
      "expected": "[null, result1, ...]"
    }
  ]
}
```

## Verification
1. Count files: `find problems -name "test_cases.json" | wc -l` → should be 16
2. Validate JSON: `python -m json.tool` on each file
3. Check content: Each file should have ≥2 test cases

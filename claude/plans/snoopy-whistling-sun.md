# Iterative Refactoring Plan with Test-First Approach (REVISED)

## Overview
Refactor GitHub Notifications MCP server with test-driven development. Each iteration: write tests first, implement changes, verify tests pass, commit.

**Revision notes**: Plan updated based on comprehensive critiques from Gemini and code-reviewer agents. Key changes:
1. Reordered: Schemas before API types (schemas define validation rules)
2. Atomic commits: Apply changes to all affected files at once (no split state)
3. Fixed: Fetch mocking uses `Headers` object, not `Map`
4. Added: Thread ID validation (security)
5. Added: Integration and composition tests

## Current Test State
- **Framework**: Jest 29.7.0 + ts-jest (configured for ESM)
- **Test runner**: `bun test` (Bun's native runner, verify Jest compatibility)
- **Existing tests**: Only 4 tests in `formatters.test.ts` (URL conversion)
- **Coverage gaps**: No tests for API utilities, tool handlers, formatters (except URL conversion)
- **Pattern**: Simple Jest describe/test blocks with direct assertions

---

## Iteration 1: Commit Bun Migration ✓

**Status**: Changes already made, needs commit only

**Changes**:
- ✅ `bun.lockb` created
- ✅ `package.json` scripts updated to use bun
- ✅ `README.md` updated with bun instructions

**Test**: `bun run build` (already verified - passes)

**Commit**:
```bash
git add bun.lockb package.json README.md
git commit -m "build: migrate from npm to bun

- Install dependencies with bun
- Update all npm scripts to use bun commands
- Update README with bun installation/usage instructions
- Build and start commands now use bun runtime"
```

---

## Iteration 2: Response Helpers (TDD)

**Goal**: Add `successResponse()` and `errorResponse()` helpers to reduce ~100 lines of boilerplate across 11 tool files.

**IMPORTANT**: Apply to ALL 11 tools at once to avoid split codebase state.

### 2.1 Write Tests First

**File**: `src/__tests__/formatters.test.ts` (add to existing file)

**New test suite**:
```typescript
describe('Response Helpers', () => {
  describe('successResponse', () => {
    test('creates success response with text content', () => {
      const result = successResponse('Operation completed');

      expect(result).toEqual({
        content: [{ type: 'text', text: 'Operation completed' }]
      });
      expect(result.isError).toBeUndefined();
    });
  });

  describe('errorResponse', () => {
    test('creates error response from Error object', () => {
      const error = new Error('Something went wrong');
      const result = errorResponse('Failed to process', error);

      expect(result.isError).toBe(true);
      expect(result.content).toHaveLength(1);
      expect(result.content[0].type).toBe('text');
      expect(result.content[0].text).toContain('Failed to process');
      expect(result.content[0].text).toContain('Something went wrong');
    });

    test('creates error response from string error', () => {
      const result = errorResponse('Failed to process', 'Network timeout');

      expect(result.isError).toBe(true);
      expect(result.content[0].text).toContain('Failed to process');
      expect(result.content[0].text).toContain('Network timeout');
    });

    test('creates error response from unknown error type', () => {
      const result = errorResponse('Failed to process', { code: 500 });

      expect(result.isError).toBe(true);
      expect(result.content[0].text).toContain('Failed to process');
    });
  });

  describe('Integration with tools', () => {
    test('response helpers work in tool handler pattern', () => {
      // Simulate what tools do
      const simulateSuccess = () => successResponse('Task completed');
      const simulateError = () => errorResponse('Task failed', new Error('Network timeout'));

      expect(simulateSuccess()).toHaveProperty('content');
      expect(simulateSuccess().isError).toBeUndefined();
      expect(simulateError()).toHaveProperty('isError', true);
    });
  });
});
```

### 2.2 Run Tests (expect failures)
```bash
bun test
# Should fail: successResponse/errorResponse not defined
```

### 2.3 Implement Helpers

**File**: `src/utils/formatters.ts` (add these exports)

```typescript
interface ToolResponse {
  isError?: boolean;
  content: Array<{ type: "text"; text: string }>;
}

export function successResponse(text: string): ToolResponse {
  return {
    content: [{ type: "text", text }]
  };
}

export function errorResponse(message: string, error: unknown): ToolResponse {
  return {
    isError: true,
    content: [{ type: "text", text: formatError(message, error) }]
  };
}
```

### 2.4 Run Tests (expect pass)
```bash
bun test
# All tests should pass
```

### 2.5 Apply to ALL 11 Tools

**Files to update** (all tools at once to avoid split state):
- `src/tools/list-notifications.ts`
- `src/tools/mark-notifications-read.ts`
- `src/tools/get-thread.ts`
- `src/tools/mark-thread-read.ts`
- `src/tools/mark-thread-done.ts`
- `src/tools/get-thread-subscription.ts`
- `src/tools/set-thread-subscription.ts`
- `src/tools/delete-thread-subscription.ts`
- `src/tools/list-repo-notifications.ts`
- `src/tools/mark-repo-notifications-read.ts`
- `src/tools/manage-repo-subscription.ts`

**Pattern**:
```typescript
// Before:
return {
  content: [{
    type: "text",
    text: `Successfully marked thread ${args.thread_id} as read.`
  }]
};

// After:
return successResponse(`Successfully marked thread ${args.thread_id} as read.`);
```

**Error handling**:
```typescript
// Before:
catch (error: any) {  // Also change to 'unknown'
  return {
    isError: true,
    content: [{
      type: "text",
      text: formatError(`Failed to mark thread ${args.thread_id} as read`, error)
    }]
  };
}

// After:
catch (error: unknown) {
  return errorResponse(`Failed to mark thread ${args.thread_id} as read`, error);
}
```

### 2.6 Verify
```bash
bun run build  # TypeScript compilation
bun test       # All tests pass
```

### 2.7 Commit
```bash
git add src/utils/formatters.ts src/__tests__/formatters.test.ts src/tools/*.ts
git commit -m "refactor: add response helpers to reduce boilerplate

- Add successResponse() and errorResponse() helpers
- Add comprehensive tests for response helpers (including integration test)
- Apply to ALL 11 tools atomically (no split state)
- Reduces ~100 lines of duplicated response formatting
- Improves type safety by accepting 'unknown' instead of 'any' for errors"
```

---

## Iteration 3: Shared Schemas (TDD)

**Goal**: Extract common schema patterns to reduce duplication and centralize validation. This defines validation rules that API and tools will use.

**Why this comes before API types**: Schemas define what parameter types are valid. API functions should accept types validated by schemas.

### 3.1 Write Tests First

**File**: `src/__tests__/schemas.test.ts` (new file)

```typescript
import { z } from 'zod';
import {
  paginationSchema,
  repoIdentifierSchema,
  notificationFilterSchema,
  timestampSchema,
  threadIdSchema
} from '../utils/schemas';

describe('Shared Schemas', () => {
  describe('paginationSchema', () => {
    test('accepts valid page and per_page', () => {
      const schema = z.object(paginationSchema);
      const result = schema.safeParse({ page: 2, per_page: 50 });
      expect(result.success).toBe(true);
    });

    test('accepts optional pagination params', () => {
      const schema = z.object(paginationSchema);
      const result = schema.safeParse({});
      expect(result.success).toBe(true);
    });

    test('accepts exactly 1 page (lower bound)', () => {
      const schema = z.object(paginationSchema);
      const result = schema.safeParse({ page: 1 });
      expect(result.success).toBe(true);
    });

    test('accepts exactly 100 page (upper bound)', () => {
      const schema = z.object(paginationSchema);
      const result = schema.safeParse({ page: 100 });
      expect(result.success).toBe(true);
    });

    test('rejects negative page numbers', () => {
      const schema = z.object(paginationSchema);
      const result = schema.safeParse({ page: -1 });
      expect(result.success).toBe(false);
    });

    test('rejects page > 100', () => {
      const schema = z.object(paginationSchema);
      const result = schema.safeParse({ page: 101 });
      expect(result.success).toBe(false);
    });

    test('rejects per_page > 100', () => {
      const schema = z.object(paginationSchema);
      const result = schema.safeParse({ per_page: 150 });
      expect(result.success).toBe(false);
    });
  });

  describe('repoIdentifierSchema', () => {
    test('accepts valid owner and repo', () => {
      const schema = z.object(repoIdentifierSchema);
      const result = schema.safeParse({ owner: 'nodejs', repo: 'node' });
      expect(result.success).toBe(true);
    });

    test('accepts repo names with hyphens', () => {
      const schema = z.object(repoIdentifierSchema);
      const result = schema.safeParse({ owner: 'my-org', repo: 'my-repo' });
      expect(result.success).toBe(true);
    });

    test('rejects empty strings', () => {
      const schema = z.object(repoIdentifierSchema);
      const result = schema.safeParse({ owner: '', repo: 'node' });
      expect(result.success).toBe(false);
    });

    test('rejects owner/repo with path traversal attempts', () => {
      const schema = z.object(repoIdentifierSchema);
      const result = schema.safeParse({ owner: '../etc', repo: 'passwd' });
      expect(result.success).toBe(false);
    });

    test('rejects owner starting with dot', () => {
      const schema = z.object(repoIdentifierSchema);
      const result = schema.safeParse({ owner: '.hidden', repo: 'test' });
      expect(result.success).toBe(false);
    });

    test('rejects encoded path traversal', () => {
      const schema = z.object(repoIdentifierSchema);
      const result = schema.safeParse({ owner: '%2e%2e%2fetc', repo: 'test' });
      expect(result.success).toBe(false);
    });
  });

  describe('threadIdSchema', () => {
    test('accepts valid numeric thread IDs', () => {
      const result = threadIdSchema.safeParse('1234567890');
      expect(result.success).toBe(true);
    });

    test('rejects non-numeric thread IDs', () => {
      const result = threadIdSchema.safeParse('abc123');
      expect(result.success).toBe(false);
    });

    test('rejects empty thread ID', () => {
      const result = threadIdSchema.safeParse('');
      expect(result.success).toBe(false);
    });

    test('rejects thread ID > 20 chars', () => {
      const result = threadIdSchema.safeParse('123456789012345678901');
      expect(result.success).toBe(false);
    });
  });

  describe('timestampSchema', () => {
    test('accepts valid ISO 8601 timestamp', () => {
      const result = timestampSchema.safeParse('2024-01-15T10:30:00Z');
      expect(result.success).toBe(true);
    });

    test('accepts timestamp with milliseconds', () => {
      const result = timestampSchema.safeParse('2024-01-15T10:30:00.123Z');
      expect(result.success).toBe(true);
    });

    test('accepts timestamp with timezone offset', () => {
      const result = timestampSchema.safeParse('2024-01-15T10:30:00+05:30');
      expect(result.success).toBe(true);
    });

    test('rejects invalid date format', () => {
      const result = timestampSchema.safeParse('2024-13-45');
      expect(result.success).toBe(false);
    });

    test('rejects non-ISO format', () => {
      const result = timestampSchema.safeParse('Jan 15, 2024');
      expect(result.success).toBe(false);
    });
  });

  describe('notificationFilterSchema', () => {
    test('accepts all valid filter combinations', () => {
      const schema = z.object(notificationFilterSchema);
      const result = schema.safeParse({
        all: true,
        participating: false,
        since: '2024-01-01T00:00:00Z',
        before: '2024-12-31T23:59:59Z',
        page: 1,
        per_page: 50
      });
      expect(result.success).toBe(true);
    });

    test('accepts empty filter object', () => {
      const schema = z.object(notificationFilterSchema);
      const result = schema.safeParse({});
      expect(result.success).toBe(true);
    });
  });

  describe('Schema Composition', () => {
    test('composed schemas preserve all validations', () => {
      const composedSchema = z.object({
        ...repoIdentifierSchema,
        ...notificationFilterSchema
      });

      // Should reject invalid repo + valid filters
      expect(composedSchema.safeParse({
        owner: '../etc',
        repo: 'passwd',
        page: 1
      }).success).toBe(false);

      // Should accept valid repo + valid filters
      expect(composedSchema.safeParse({
        owner: 'nodejs',
        repo: 'node',
        page: 2,
        per_page: 50
      }).success).toBe(true);
    });
  });
});
```

### 3.2 Run Tests (expect failures)
```bash
bun test
# Should fail: schemas not yet defined
```

### 3.3 Create Shared Schemas

**File**: `src/utils/schemas.ts` (new file)

```typescript
import { z } from "zod";

/**
 * Common pagination parameters used across list endpoints
 */
export const paginationSchema = {
  page: z.number()
    .int("Page must be a whole number")
    .min(1, "Page must be at least 1")
    .max(100, "GitHub API limits pagination to 100 pages")
    .optional()
    .describe("Page number for pagination (1-100)"),
  per_page: z.number()
    .int("Items per page must be a whole number")
    .min(1, "Must request at least 1 item per page")
    .max(100, "GitHub API maximum is 100 items per page")
    .optional()
    .describe("Number of results per page (1-100, default 30)")
};

/**
 * GitHub repository identifier with strict validation and security checks
 */
export const repoIdentifierSchema = {
  owner: z.string()
    .min(1, "Owner cannot be empty")
    .max(39, "GitHub username maximum length is 39 characters")
    .regex(
      /^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?$/,
      "Owner must start and end with alphanumeric characters, may contain hyphens"
    )
    .describe("The account owner of the repository"),
  repo: z.string()
    .min(1, "Repository name cannot be empty")
    .max(100, "Repository name maximum length is 100 characters")
    .regex(
      /^[a-zA-Z0-9._-]+$/,
      "Repository name can only contain alphanumeric characters, dots, underscores, and hyphens"
    )
    .refine(
      val => {
        const decoded = decodeURIComponent(val);
        return !decoded.includes('..') &&
               !decoded.includes('\0') &&
               !decoded.includes('/') &&
               !decoded.includes('\\') &&
               !decoded.startsWith('.');
      },
      "Repository name contains invalid characters or path traversal attempts"
    )
    .describe("The name of the repository")
};

/**
 * GitHub notification thread ID validation
 */
export const threadIdSchema = z.string()
  .min(1, "Thread ID cannot be empty")
  .max(20, "Thread ID too long")
  .regex(/^\d+$/, "Thread ID must be numeric")
  .describe("GitHub notification thread ID");

/**
 * ISO 8601 timestamp validation
 */
export const timestampSchema = z.string()
  .max(64, "Timestamp exceeds maximum length")
  .regex(
    /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$/,
    "Must be a valid ISO 8601 timestamp (e.g., 2024-01-15T10:30:00Z)"
  )
  .describe("ISO 8601 formatted timestamp");

/**
 * Common notification filtering parameters
 */
export const notificationFilterSchema = {
  all: z.boolean()
    .optional()
    .describe("If true, show notifications marked as read (default: false)"),
  participating: z.boolean()
    .optional()
    .describe("If true, only show notifications for threads you're directly participating in"),
  since: timestampSchema
    .optional()
    .describe("Only show notifications updated after this time"),
  before: timestampSchema
    .optional()
    .describe("Only show notifications updated before this time"),
  ...paginationSchema
};
```

### 3.4 Run Tests (expect pass)
```bash
bun test
# All schema tests should pass
```

### 3.5 Apply to Tools

**Files to update**:
- `src/tools/list-notifications.ts`
- `src/tools/list-repo-notifications.ts`
- `src/tools/mark-repo-notifications-read.ts`
- `src/tools/manage-repo-subscription.ts`
- `src/tools/get-thread.ts`
- `src/tools/mark-thread-read.ts`
- `src/tools/mark-thread-done.ts`
- `src/tools/get-thread-subscription.ts`
- `src/tools/set-thread-subscription.ts`
- `src/tools/delete-thread-subscription.ts`

**Pattern**:
```typescript
// Add import:
import { notificationFilterSchema, repoIdentifierSchema, threadIdSchema } from "../utils/schemas.js";

// Update schema:
// Before (list-notifications.ts):
export const listNotificationsSchema = z.object({
  all: z.boolean().optional().describe("If true, show notifications marked as read"),
  participating: z.boolean().optional().describe("If true, only shows notifications where user is directly participating"),
  since: z.string().optional().describe("ISO 8601 timestamp - only show notifications updated after this time"),
  before: z.string().optional().describe("ISO 8601 timestamp - only show notifications updated before this time"),
  page: z.number().optional().describe("Page number for pagination"),
  per_page: z.number().optional().describe("Number of results per page (max 100)")
});

// After:
export const listNotificationsSchema = z.object(notificationFilterSchema);

// Before (list-repo-notifications.ts):
export const listRepoNotificationsSchema = z.object({
  owner: z.string().describe("The account owner of the repository"),
  repo: z.string().describe("The name of the repository"),
  all: z.boolean().optional().describe("If true, show notifications marked as read"),
  // ... same filters as above
});

// After:
export const listRepoNotificationsSchema = z.object({
  ...repoIdentifierSchema,
  ...notificationFilterSchema
});

// Before (get-thread.ts):
export const getThreadSchema = z.object({
  thread_id: z.string().describe("The ID of the notification thread to retrieve")
});

// After:
export const getThreadSchema = z.object({
  thread_id: threadIdSchema
});
```

### 3.6 Verify
```bash
bun run build  # TypeScript compilation
bun test       # All tests pass, including new schema tests
```

### 3.7 Commit
```bash
git add src/utils/schemas.ts src/__tests__/schemas.test.ts src/tools/*.ts
git commit -m "refactor: extract shared Zod schemas with security validations

- Create src/utils/schemas.ts with reusable schema definitions
- Add paginationSchema with validation (1-100 page, 1-100 per_page)
- Add repoIdentifierSchema with path traversal protection (including encoded)
- Add threadIdSchema for thread ID validation (numeric, max 20 chars)
- Add timestampSchema for ISO 8601 validation
- Add notificationFilterSchema combining common filters
- Comprehensive test suite for all schemas (including composition tests)
- Apply to all 10 relevant tools atomically
- Reduces schema duplication and improves input validation security"
```

---

## Iteration 4: Type Safety - API Utilities (TDD)

**Goal**: Replace `Record<string, any>` with specific types in `api.ts`. Uses schemas from Iteration 3 for param validation.

### 4.1 Create Mock Helper First

**File**: `src/__tests__/test-helpers.ts` (new file)

**CRITICAL FIX**: Use `Headers` object, not `Map` for Response mocking.

```typescript
/**
 * Helper to create mock Response for API testing
 * IMPORTANT: Uses Headers object (not Map) to match actual Response interface
 */
export function createMockResponse(
  body: any,
  status: number = 200,
  headers: Record<string, string> = {}
): Response {
  const mockHeaders = new Headers();
  Object.entries(headers).forEach(([k, v]) => mockHeaders.set(k, v));

  return {
    ok: status >= 200 && status < 300,
    status,
    headers: mockHeaders,
    url: 'https://api.github.com/test',
    json: async () => body,
  } as Response;
}
```

### 4.2 Write Tests First

**File**: `src/__tests__/api.test.ts` (new file)

```typescript
import { jest } from '@jest/globals';
import { githubGet, githubPut, githubPatch, githubDelete } from '../utils/api';
import { createMockResponse } from './test-helpers';

describe('API Utilities', () => {
  let mockFetch: jest.MockedFunction<typeof fetch>;

  beforeEach(() => {
    mockFetch = jest.fn();
    global.fetch = mockFetch as any;
    process.env.GITHUB_TOKEN = 'test_token_123';
  });

  afterEach(() => {
    jest.restoreAllMocks();
  });

  describe('githubGet parameter handling', () => {
    test('accepts string params', async () => {
      mockFetch.mockResolvedValue(createMockResponse(
        { data: 'test' },
        200,
        {
          'x-ratelimit-limit': '5000',
          'x-ratelimit-remaining': '4999',
          'x-ratelimit-reset': '1234567890'
        }
      ));

      await githubGet('/test', { params: { filter: 'all', page: '1' } });

      const callUrl = mockFetch.mock.calls[0][0] as string;
      expect(callUrl).toContain('filter=all');
      expect(callUrl).toContain('page=1');
    });

    test('accepts number params', async () => {
      mockFetch.mockResolvedValue(createMockResponse({ data: 'test' }, 200, {
        'x-ratelimit-limit': '5000',
        'x-ratelimit-remaining': '4999',
        'x-ratelimit-reset': '1234567890'
      }));

      await githubGet('/test', { params: { per_page: 50, page: 2 } });

      const callUrl = mockFetch.mock.calls[0][0] as string;
      expect(callUrl).toContain('per_page=50');
      expect(callUrl).toContain('page=2');
    });

    test('accepts boolean params', async () => {
      mockFetch.mockResolvedValue(createMockResponse({ data: 'test' }, 200, {
        'x-ratelimit-limit': '5000',
        'x-ratelimit-remaining': '4999',
        'x-ratelimit-reset': '1234567890'
      }));

      await githubGet('/test', { params: { all: true, participating: false } });

      const callUrl = mockFetch.mock.calls[0][0] as string;
      expect(callUrl).toContain('all=true');
      expect(callUrl).toContain('participating=false');
    });

    test('skips undefined params', async () => {
      mockFetch.mockResolvedValue(createMockResponse({ data: 'test' }, 200, {
        'x-ratelimit-limit': '5000',
        'x-ratelimit-remaining': '4999',
        'x-ratelimit-reset': '1234567890'
      }));

      await githubGet('/test', { params: { filter: 'all', empty: undefined } });

      const callUrl = mockFetch.mock.calls[0][0] as string;
      expect(callUrl).toContain('filter=all');
      expect(callUrl).not.toContain('empty');
    });

    test('encodes special characters', async () => {
      mockFetch.mockResolvedValue(createMockResponse({ data: 'test' }, 200, {
        'x-ratelimit-limit': '5000',
        'x-ratelimit-remaining': '4999',
        'x-ratelimit-reset': '1234567890'
      }));

      await githubGet('/test', { params: { query: 'foo bar' } });

      const callUrl = mockFetch.mock.calls[0][0] as string;
      expect(callUrl).toContain('query=foo%20bar');
    });
  });

  describe('Error Handling', () => {
    test('handles 404 errors', async () => {
      mockFetch.mockResolvedValue(createMockResponse(
        { message: 'Not Found' },
        404,
        {
          'x-ratelimit-limit': '5000',
          'x-ratelimit-remaining': '4999',
          'x-ratelimit-reset': '1234567890'
        }
      ));

      await expect(githubGet('/test')).rejects.toThrow('Resource not found');
    });

    test('handles 401 errors', async () => {
      mockFetch.mockResolvedValue(createMockResponse(
        { message: 'Unauthorized' },
        401,
        {
          'x-ratelimit-limit': '5000',
          'x-ratelimit-remaining': '4999',
          'x-ratelimit-reset': '1234567890'
        }
      ));

      await expect(githubGet('/test')).rejects.toThrow('Authentication required');
    });

    test('handles rate limiting', async () => {
      mockFetch.mockResolvedValue(createMockResponse(
        { message: 'API rate limit exceeded' },
        403,
        {
          'x-ratelimit-limit': '5000',
          'x-ratelimit-remaining': '0',
          'x-ratelimit-reset': '1234567890'
        }
      ));

      await expect(githubGet('/test')).rejects.toThrow('rate limit exceeded');
    });
  });
});
```

### 4.3 Run Tests (expect pass with current types)

**NOTE**: These tests will PASS with `Record<string, any>` because JavaScript is dynamically typed. We're testing runtime behavior before refactoring compile-time types.

```bash
bun test
# Tests should pass - we're documenting current behavior
```

### 4.4 Update Types

**File**: `src/utils/api.ts`

**CRITICAL**: Use `unknown` as default (not removing default entirely) to avoid breaking all callers.

```typescript
// Before:
export interface RequestOptions {
  params?: Record<string, any>;
  headers?: Record<string, string>;
}

// After:
export type ParamValue = string | number | boolean | undefined;

export interface RequestOptions {
  params?: Record<string, ParamValue>;
  headers?: Record<string, string>;
}

// Before:
function buildUrl(path: string, params?: Record<string, any>): string {

// After:
function buildUrl(path: string, params?: Record<string, ParamValue>): string {

// Before:
export async function githubGet<T = any>(path: string, options: RequestOptions = {}): Promise<T> {

// After:
export async function githubGet<T = unknown>(path: string, options: RequestOptions = {}): Promise<T> {

// Apply same pattern to githubPut, githubPatch, githubDelete
```

### 4.5 Verify
```bash
bun run build  # TypeScript will catch any type mismatches
bun test       # All tests should still pass
```

### 4.6 Commit
```bash
git add src/utils/api.ts src/__tests__/api.test.ts src/__tests__/test-helpers.ts
git commit -m "refactor: improve type safety in API utilities

- Replace Record<string, any> with Record<string, ParamValue>
- Define ParamValue = string | number | boolean | undefined
- Change default generic from 'any' to 'unknown' (safer, non-breaking)
- Add comprehensive API utility tests with proper Headers mocking
- Test param handling (string, number, boolean, undefined, encoding)
- Test error handling (401, 403, 404, rate limiting)
- Create test-helpers.ts with createMockResponse utility"
```

---

## Iteration 5: Type Safety - MCP Server Parameter

**Goal**: Replace `server: any` with `McpServer` type in all tool registration functions.

### 5.1 No New Tests Needed
- Type checking is done by TypeScript compiler
- Existing tool functionality doesn't change
- Tests from previous iterations cover behavior

### 5.2 Update Type Annotations

**Files to update** (11 files):
- `src/tools/list-notifications.ts`
- `src/tools/mark-notifications-read.ts`
- `src/tools/get-thread.ts`
- `src/tools/mark-thread-read.ts`
- `src/tools/mark-thread-done.ts`
- `src/tools/get-thread-subscription.ts`
- `src/tools/set-thread-subscription.ts`
- `src/tools/delete-thread-subscription.ts`
- `src/tools/list-repo-notifications.ts`
- `src/tools/mark-repo-notifications-read.ts`
- `src/tools/manage-repo-subscription.ts`

**Pattern for each file**:
```typescript
// Add import at top:
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";

// Update function signature:
// Before:
export function registerListNotificationsTool(server: any) {

// After:
export function registerListNotificationsTool(server: McpServer): void {
```

### 5.3 Verify
```bash
bun run build  # TypeScript will verify McpServer interface compatibility
bun test       # Existing tests should still pass
```

### 5.4 Commit
```bash
git add src/tools/*.ts
git commit -m "refactor: add proper types for MCP server parameter

- Import McpServer type from SDK in all tool files
- Replace 'server: any' with 'server: McpServer' in 11 registration functions
- Add explicit void return type for clarity
- No functional changes, type safety improvement only"
```

---

## Iteration 6: Cleanup

**Goal**: Remove dead code, fix version mismatch, remove duplicate checks.

### 6.1 No New Tests Needed
- Removing code, not adding functionality
- TypeScript compilation will catch any issues

### 6.2 Changes

**File**: `src/server.ts` (line 29)
```typescript
// Before:
const server = new McpServer({
  name: "github-notifications",
  version: "1.0.0"  // Doesn't match package.json
}, ...);

// After:
const server = new McpServer({
  name: "github-notifications",
  version: "1.1.0"  // Match package.json
}, ...);
```

**File**: `src/utils/api.ts` (lines 5-9)
```typescript
// REMOVE this duplicate check (already in index.ts):
if (!process.env.GITHUB_TOKEN) {
  console.error("Error: GITHUB_TOKEN environment variable is required");
  process.exit(1);
}
```

**File**: `src/tools/manage-repo-subscription.ts` (line 39 and lines 15-21)
```typescript
// Remove unused 'options' parameter from destructuring:
// Before:
const { owner, repo, action, options } = args;

// After:
const { owner, repo, action } = args;

// Also remove options from schema definition (lines 15-21)
// Remove the entire options field:
// options: z.object({
//   subscribed: z.boolean().optional()...
//   ignored: z.boolean().optional()...
// }).optional()...
```

**File**: Multiple tool files
```typescript
// Remove obvious comments like:
// "Make request to GitHub API"
// "Prepare request body"
```

### 6.3 Verify
```bash
bun run build  # TypeScript compilation
bun test       # All tests still pass
bun start      # Quick smoke test that server starts (Ctrl+C after)
```

### 6.4 Commit
```bash
git add src/server.ts src/utils/api.ts src/tools/manage-repo-subscription.ts src/tools/*.ts
git commit -m "refactor: remove dead code and fix inconsistencies

- Fix version mismatch: update server.ts to 1.1.0 (matches package.json)
- Remove duplicate GITHUB_TOKEN check in api.ts (already in index.ts)
- Remove unused 'options' parameter in manage-repo-subscription
- Remove obvious comments that just restate code
- No functional changes"
```

---

## Security Hardening (Future Work)

**Not part of current iteration** - These require more substantial testing and are partially addressed:

### Already Addressed (Iteration 3)
- ✅ Path traversal protection (repoIdentifierSchema with encoded traversal checks)
- ✅ ISO 8601 timestamp validation
- ✅ Pagination bounds (1-100)
- ✅ Repo name character restrictions
- ✅ Thread ID format validation (numeric, max 20 chars)

### Still Deferred
1. **Rate limiting improvements**
   - Needs tests for retry logic, exponential backoff
   - Should test rate limit edge cases

2. **Error message sanitization**
   - Needs tests to verify no sensitive info leaked
   - Should test various error types

**Recommendation**: Address remaining security issues in a separate focused session after refactoring is complete.

---

## Verification Strategy

After each iteration:

1. **Type Check**: `bun run build`
   - Catches type errors immediately
   - Ensures TypeScript compilation succeeds

2. **Unit Tests**: `bun test`
   - Runs all Jest tests
   - Should show passing tests increasing with each iteration

3. **Smoke Test**: `bun start` (Ctrl+C after startup)
   - Verifies server initializes without errors
   - Checks that all tools register successfully

4. **Git Status**: `git status`
   - Verify only intended files changed
   - Check for any untracked files that should be ignored

5. **Rollback (if needed)**:
   ```bash
   git reset --soft HEAD~1  # Undo commit, keep changes
   # OR
   git revert HEAD          # Create revert commit
   ```

---

## Critical Files Reference

**Will be modified**:
- `src/utils/formatters.ts` - Add response helpers
- `src/utils/api.ts` - Type safety improvements, remove duplicate check
- `src/utils/schemas.ts` - NEW: Shared Zod schemas with security validations
- `src/__tests__/formatters.test.ts` - Add response helper tests
- `src/__tests__/api.test.ts` - NEW: API utility tests
- `src/__tests__/schemas.test.ts` - NEW: Schema validation tests (including composition)
- `src/__tests__/test-helpers.ts` - NEW: Mock response helper
- `src/tools/*.ts` (11 files) - Apply helpers, add types, use shared schemas
- `src/server.ts` - Fix version number
- `package.json` - Already updated (bun migration)
- `README.md` - Already updated (bun migration)

**Test coverage progression**:
- Current: 4 tests (URL conversion only)
- After Iteration 2: ~15 tests (+ response helpers + integration)
- After Iteration 3: ~55 tests (+ schemas + composition)
- After Iteration 4: ~70 tests (+ API utilities)

---

## Summary

This plan follows test-driven development with critical fixes:
1. ✅ **Reordered**: Schemas before API (schemas define validation rules)
2. ✅ **Atomic commits**: All affected files updated together (no split state)
3. ✅ **Fixed mocking**: Use `Headers` object, not `Map`
4. ✅ **Added security**: Thread ID validation, encoded path traversal checks
5. ✅ **Added tests**: Integration tests, schema composition tests
6. ✅ **Safe generics**: Use `T = unknown` instead of removing defaults

Each iteration is small (10-20 min), testable, and independently valuable.

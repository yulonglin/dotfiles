# Classifier attribution repair misses gateway URLs

Draft only; not filed. A human must decide whether to post this as a new issue or follow up on the existing threads.

## Gateway requests still hit 429s

Claude Code's auto-mode classifier returned bare HTTP 429 responses when `CLAUDE_CODE_ATTRIBUTION_HEADER=0` was set and Anthropic-bound requests went through a custom model-router base URL. Removing the variable restored classifier verdicts without disabling the gateway. The observed failure blocked tool execution; we did not demonstrate silent approval after a backend error.

The [existing explanation on #49535](https://github.com/anthropics/claude-code/issues/49535#issuecomment-5491600660) describes this gateway gap in the repair associated with [#64585](https://github.com/anthropics/claude-code/issues/64585) and [#60438](https://github.com/anthropics/claude-code/issues/60438)

## Setup

- Client code inspected: Claude Code 2.1.263; the local incident report covers failures through 2.1.267. This draft does not claim a reproduction on the latest release.
- Permission mode: auto mode, with a native classifier request required before the test's Bash action.
- Routing: a custom base URL pointing to a local model-router gateway that forwarded Anthropic requests. This was not a test of a foreign model's approval behavior.
- Configuration: `CLAUDE_CODE_ATTRIBUTION_HEADER=0` and `_CLAUDE_CODE_ASSUME_FIRST_PARTY_BASE_URL` were present in the failing gateway setup.
- Sources: [local root-cause report](https://github.com/yulonglin/dotfiles/blob/f21ae7e/artifacts/auto-mode-classifier-429/report.md) and [workaround commit b2868c8](https://github.com/yulonglin/dotfiles/commit/b2868c8a3b2c97b91adbd0b1b8cd81d24efd38be)

## Methods

The recorded test used a headless auto-mode session asked to create and remove a disposable file in one Bash command. Classifier request captures were inspected separately from the conversation transcript. The same file-operation probe ran before and after removing the attribution opt-out.

To repeat the comparison in an isolated test configuration:

1. Record the CLI version and confirm the running session is in auto mode, not merely configured to start in it. Ensure the test action is not pre-approved by a rule or sandbox setting.
2. With the gateway and opt-out enabled, ask the session to create and remove a disposable scratch file. Record classifier response status, any verdict and whether the command runs.
3. Remove only the opt-out from the test configuration. Start a new session through the same gateway and repeat the action.
4. Repeat against the direct Anthropic endpoint as a separate control. Do not label a loopback capture proxy as a direct connection: the custom URL itself is part of the trigger.

Keep authentication and routing unchanged between the gateway runs. Keep request captures private; share only sanitized status and verdict summaries. These are reproduction instructions, not a request to modify a live configuration.

## Removing the opt-out restored verdicts

The report records these runs; they have not been repeated for this draft.

| Date | Route | Attribution opt-out | Recorded result |
|---|---|---|---|
| 8 September 2026 | Model-router gateway | Set | 15 classifier requests, all 429; every Bash denied; command never ran |
| 8 September 2026 | Comparison capture proxy | Set | 15 classifier requests, all 429; command never ran |
| 9 September 2026 | Model-router gateway | Removed | Verdicts returned; command completed; zero denials; three turns |
| 9 September 2026 | Direct Anthropic connection | Removed | Verdicts returned; command completed; zero denials; three turns |

The two failing runs both used custom base URLs. They did not isolate gateway forwarding as a cause. The report names job-local raw captures that may have been reaped; this draft relies on the committed summary and does not attach those captures. Its historical timeline also records two 429s on a gateway-off day, so it does not establish that all classifier 429s have this cause.

## The repair checks the URL

The reported inspection of Claude Code 2.1.263 found that the classifier's attribution repair reinserted the required block only when the base URL was unset or its host was `api.anthropic.com`. A custom gateway URL missed that repair even with `_CLAUDE_CODE_ASSUME_FIRST_PARTY_BASE_URL` set. The observed bare 429 therefore appeared to be a rate limit but was resolved by changing attribution configuration.

Expected behavior: supported Anthropic-bound classifier requests through a gateway should retain the attribution required by the backend. If this configuration is unsupported, the client should explain that explicitly instead of retrying an opaque 429.

## Please cover supported gateway routing

- Confirm whether the URL-only guard remains in current releases and which gateway configurations are supported.
- Apply the classifier attribution repair consistently for supported Anthropic-bound routes, without asking gateways to synthesize attribution or extending trust to arbitrary hosts.
- Add regression coverage for direct and gateway routes, with the opt-out both set and absent; check request construction and returned verdicts.
- Distinguish a missing-attribution response from a retryable rate limit in the diagnostic shown to the user.

The local workaround is already committed in [b2868c8](https://github.com/yulonglin/dotfiles/commit/b2868c8a3b2c97b91adbd0b1b8cd81d24efd38be). No router, hook or permission-policy change was needed for that workaround.

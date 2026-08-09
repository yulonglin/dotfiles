# Interview Conventions

How spec interviews (`/spec-interview`, `/spec-interview-research`, `/grill-me`, and the spec-loop plan phase) collect decisions from Yulong.

**Channel by question count.** Four questions or fewer → one batched `AskUserQuestion` call. More than four → a single markdown answer file delivered via `SendUserFile`, never a sequence of prompts.

**Answer-file format.** Each question carries a short what-I-found preamble, checkbox options with the recommended default listed FIRST and marked "(recommended)", and a `Comments:` line. A question left blank means the recommended default is accepted. (Checkboxes are permitted here as an exception to `markdown-style.md` — an answer file is a working form, not a doc.)

**Bounded rounds.** At most two rounds per interview. Round two contains only questions that round one's answers newly raised or left genuinely unresolved — a question answered in any earlier round is never re-asked, and its answer is restated as a settled decision rather than reopened.

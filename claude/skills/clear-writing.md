---
name: clear-writing
description: Write clearly without LLM-isms. Reference when drafting papers, blogs, or professional communications.
---

# Clear Writing

This skill helps you write clearly without typical LLM patterns. Use it when drafting technical content, papers, or professional communications.

## The Problem with LLM Writing

LLM outputs often share recognizable patterns:
- **Hedging phrases**: "It's worth noting that...", "Interestingly...", "This is particularly important because..."
- **False enthusiasm**: "Great question!", "Absolutely!", "This is a fascinating area..."
- **Padding**: Restating the question, excessive context-setting, unnecessary conclusions
- **Uniformity**: Every paragraph same length, predictable structure, no voice
- **Avoidance**: Refusing to take positions, always presenting "both sides"

Good writing has texture. It makes choices. It sounds like a person who has opinions.

## Reference Material

Study these examples for calibration:

### ML Papers (Clarity Under Constraint)

**AI Control (ICML 2024)**
- OpenReview: https://openreview.net/forum?id=7Jk9zBkJDq
- Clear problem framing in first paragraph, no wasted words
- Precise threat models stated upfront
- Tables that actually help (not decorative)

**Debate paper (Perez et al.)**
- "Towards Understanding Sycophancy in Language Models"
- Direct claims: "We find X" not "Our results suggest that X may potentially..."
- Figures earn their space

**What to notice:**
- First sentences of sections do real work
- Concrete examples before abstractions
- Limitations stated matter-of-factly, not apologetically

### Technical Blogs (Voice + Depth)

**Ferenc Huszár** (https://www.inference.vc/)
- Conversational without being sloppy
- Takes positions, argues for them
- Mathematical clarity with intuition first
- Example: "The Two Cultures of Machine Learning"

**Anthropic Alignment Science** (https://www.anthropic.com/research)
- Clean prose, no padding
- "We did X. We found Y. This suggests Z."
- Acknowledges uncertainty without hedging everything

**Lilian Weng** (https://lilianweng.github.io/)
- Dense information, well-organized
- Good for comprehensive overviews
- Clear section structure helps navigation

**Andrej Karpathy** (https://karpathy.github.io/, @karpathy)
- Approachable explanations of hard concepts
- "A Recipe for Training Neural Networks"
- First-person, specific, actionable

**Dario Amodei**
- "Machines of Loving Grace" essay
- Long-form with clear argument structure
- Ambitious scope with honest uncertainty

### Slack and Email (Concise Professional)

**Good Slack:**
- Lead with the ask or key point
- Context after, not before
- "Can you review PR #123? It changes auth flow." Not "Hey! Hope you're doing well. I was wondering if you might have a moment to..."

**Good email:**
- Subject line that's actually useful
- First sentence answers "why am I reading this?"
- Action items explicit and at the end
- Skip the pleasantries in ongoing threads

## Good Patterns

### Honest Uncertainty
State what you know and don't know. Overclaiming erodes trust.

- "We observed X in 3/5 runs" not "X consistently occurs"
- "This suggests Y, though we haven't tested Z" not "This proves Y"
- "~80% confident" or "speculative" when appropriate
- Limitations matter-of-factly, not buried or apologetic

### Signposting
Help readers navigate. Signposts are good, not padding.

- "Three factors matter here: A, B, and C." (then discuss each)
- "First... Second... Finally..."
- "The key insight is..."
- Section headers that actually describe content

### Punctuation
- **Avoid em-dashes** as parentheticals. Use commas or parentheses instead.
  - Not: "The model performed well—surprisingly well—on the benchmark"
  - Better: "The model performed well (surprisingly well) on the benchmark"
- Colons work well before lists or explanations
- Semicolons connect related independent clauses; use sparingly

### Emojis
Acceptable in informal contexts (Slack, casual docs, slides), but bias towards restraint.
- Default to zero; add only if they genuinely help
- One or two per message max in Slack
- Never in academic papers
- Can aid signposting in Slack/slides: "🎯 Key finding:", "⚠️ Caveat:"
- Overuse reads as unserious or trying too hard

## Anti-Patterns to Avoid

### Word-Level
| Instead of | Write |
|------------|-------|
| "It's worth noting that" | (just state it) |
| "Interestingly" | (if interesting, show why) |
| "This is particularly important" | (importance should be obvious) |
| "In this section, we will discuss" | (just discuss it) |
| "As mentioned earlier" | (readers can scroll) |
| "leverage" | "use" |
| "utilize" | "use" |
| "facilitate" | "help" or "enable" |
| "in order to" | "to" |
| "is able to" | "can" |
| "a number of" | "several" or specific number |

### Structure-Level
| Instead of | Do |
|------------|-----|
| Restating the question | Answer directly |
| "There are several reasons..." then listing | Just list the reasons |
| Conclusion that restates intro | Add new insight or call to action |
| Uniform paragraph lengths | Vary based on content |
| Bullet points for everything | Use prose when flow matters |

### Tone-Level
| Instead of | Do |
|------------|-----|
| "Great question!" | Answer the question |
| "Absolutely!" | State your position |
| "That's a really interesting point" | Engage with it |
| "I hope this helps!" | (just end) |

## Applying This Skill

### When Drafting Papers
1. Write the claim first, then support
2. Cut "we believe", "we think", "it seems"—just state it
3. Use active voice: "We trained" not "Training was performed"
4. One idea per paragraph
5. Read Strunk & White, then ignore half of it

### When Drafting Blogs
1. Strong opening hook—why should I care?
2. Personal voice is fine, even good
3. Code examples should be runnable
4. Link to sources, don't summarize endlessly

### When in Slack/Email
1. Lead with the point
2. Use formatting (bold, bullets) to aid scanning
3. "Does Tuesday 2pm work?" not "I was wondering if you might be available..."
4. Assume goodwill, skip excessive politeness

### General Rules
- Delete "In conclusion" and write something better
- If removing a sentence doesn't hurt, remove it
- Read it aloud—where do you stumble?
- Would a human actually say this?

## Checklist Before Sending

- [ ] First sentence makes a claim or asks something
- [ ] No "It's worth noting", "Interestingly", "leverage/utilize"
- [ ] Paragraphs vary in length
- [ ] Active voice where possible
- [ ] Could a smart colleague skim this and get the point?
- [ ] Would you read this if someone else wrote it?

## Self-Test

Take something you wrote. Ask:
1. Can I cut the first paragraph entirely?
2. Where am I hedging that I should just commit?
3. Does the structure serve the content, or is it template-shaped?
4. Would this sound weird if I said it out loud?

Good writing requires opinions. Take positions. Be wrong sometimes. Sound like yourself.

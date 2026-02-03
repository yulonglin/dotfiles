Let's start by figuring out and revising this doc. Also spin up agents to do web search to figure out what the best practices are, from places like Twitter, Reddit, Hackernews, articles from well-known people like Simon Willinson, etc.

Look at the options for Claude to manage memory:
1. what we have locally: CLAUDE.md, README.md, specs, ai_docs, docs, tasks, plans, todos, tmp, etc.
2. https://github.com/thedotmack/claude-mem
3. https://github.com/supermemoryai/claude-supermemory
4. https://github.com/steveyegge/beads
5. Ad-hoc stuff: 
  6. https://github.com/affaan-m/everything-claude-code/tree/main/skills/continuous-learning-v2
  7. https://github.com/affaan-m/everything-claude-code/tree/main/skills/continuous-learning
  8. https://github.com/affaan-m/everything-claude-code/blob/main/hooks/hooks.json

Consider what makes sense and what we should implement:
1. /interview me to figure out what makes sense
2. Use agents to summarise the current approaches for the various projects, doing git clones if helpful
3. Let's discuss what makes sense

The types of things I use coding agents for can be seen from the convo histories. I use them to write papers, run experiments, brainstorm ideas for experiments, learn about things, write messages, write apps, connect/summarise things from Notion/Slack/etc., further optimise my code, do research / lit reviews, find recs/best practices about stuff, the sky is the limit basically

I currently believe that the specs workflow is fine, I don't know what todos is doing there. tmp is a bit random. I'd prefer .docs or .ai_docs as opposed to ai_docs or docs. Tasks are a bit annoying because they are accessible across Claude Code sessions and Claude can be confused and try to do stuff belonging to another session's.

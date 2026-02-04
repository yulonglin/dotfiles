# MATS #ai-tools Channel Summary (Full Year: March 2025 - February 2026)

*Channel Purpose: "Channel for discussing AI tools for productivity" (114 members)*

Based on comprehensive analysis of all messages from March 2025 through February 2026.

---

## 🌟 Most Recommended Tools

### **Claude Code** - Primary Coding Assistant
**Adoption Timeline**:
- March 2025: Waitlist removed, became freely available
- Install: `npm install -g @anthropic-ai/claude-code`
- Multiple scholars report using it extensively

**Key Advocates**:
- Alex Turner: "Have taken the Claude Code pill via the web interface, spinning up VMs on branches easily. Has been insane" (Feb 2026)
- Nathan Helm-Burger: Multiple tool recommendations and workflows shared

**Resources**:
- Full-time SWE best practices: [Reddit guide](https://www.reddit.com/r/ClaudeAI/comments/1oivjvm/claude_code_is_a_beast_tips_from_6_months_of/)
- Claude Code on web (Oct 2025): Can delegate tasks without opening terminal

### **Cursor AI** - Alternative/Complementary Tool
**Major Updates**:
- **Cursor 2.0** (Oct 2025): New coding model, agent interface, shareable commands/rules
- **Debug Mode** introduced (Dec 2025)
- **Agents feature** for more autonomous work (Nov 2025)

**Comparisons**:
- Clément: "Something annoying with claude code compared to cursor is that I cant edit its suggestions"
- Multiple people asking "Have any of you messed around with codex? Heard it's better than claude code"

### **Context7 Plugin** ⭐
**Recommendation by Yonatan Cale** (Jan 2026):
> "The one plugin I find myself recommending most is context7, which lets claude get docs for various things it might want to use such as inspect."

- Referenced in [claude-plugins-official marketplace.json](https://github.com/anthropics/claude-plugins-official/blob/main/.claude-plugin/marketplace.json#L566)
- Install: In Claude Code → `/plugins` → search for context7

### **Superpowers Plugin**
**Brainstorming skill particularly useful** (Yonatan Cale, Jan 2026):
- [Brainstorming skill](https://github.com/obra/superpowers/blob/main/skills/brainstorming/SKILL.md)
- Install: `/plugins` in Claude Code → search for "superpowers"
- [Referenced in claude-plugins-official](https://github.com/anthropics/claude-plugins-official/blob/main/.claude-plugin/marketplace.json#L604)

### **Anthropic Research Tools**
1. **Petri** (Oct 2025): Open-source AI auditing tool - [Blog post](https://alignment.anthropic.com/2025/petri/)
   - Auto-probes and detects bad behaviors in models
   - MATS scholars helped create it
   - 5 heart_eyes reactions

2. **Petri v2** (Jan 2026): Various improvements - [Blog post](https://alignment.anthropic.com/2026/petri-v2/)

3. **Bloom** (Jan 2026): Automated behavioral evaluations - [Anthropic blog](https://www.anthropic.com/research/bloom)
   - Complements Petri
   - Petri for exploration → Bloom for measurement
   - Authors: Isha Gupta, Kai Fronsdal, Abhay Sheshadri, Jonathan Michala, Sara Price (MATS fellows/staff)

### **Neel Nanda's Seer**
**Interpretability research library** (Dec 2025):
- [GitHub: ajobi-uhc/seer](https://github.com/ajobi-uhc/seer)
- Quality of life improvements for Claude Code in research
- Includes 250 free Modal credits for remote GPUs
- Demos: replicating introspection paper, building black box auditing agents, using SAEs to diff models

---

## 💡 Workflows & Best Practices

### Coding Workflows

#### **Test-Driven Development with AI**
**Source**: [LessWrong: How I force LLMs to generate correct code](https://www.lesswrong.com/posts/WNd3Lima4qrQ3fJEN/how-i-force-llms-to-generate-correct-code)

**Unvibe approach**:
1. LLM generates multiple code alternatives
2. Auto-run unit tests (pytest/unittest)
3. Feed failing test errors back to LLM
4. Tree search maximizes passing assertions
5. Iterate until tests pass

Question raised: How to implement this with Cursor?

#### **Experiment End-to-End Workflow** (Daniel Tan, Jan 2026)
1. Interactively draft detailed experiment spec
2. Open as GitHub issue (includes intended artifacts/reports)
3. Use Ralph Wiggum plugin to get Claude Code to address issue, open PR
4. Check back later for completion status

**Goal**: Describe experiments → hand off to agent → check completion

#### **Parallel Agent Orchestration**
**Nathan Helm-Burger** (Jan 2026): "If you want to get the most out of a Claude Pro Max 20x plan, you need to think beyond single thread usage"

**Resource**: [Welcome to Gas Town](https://steve-yegge.medium.com/welcome-to-gas-town-4f25ee16dd04) - parallel agent orchestration schemes

#### **Multiple Claude Code Instances** (Alex Turner, Jan 2028)
- Web UI allows multiple instances
- Separate VMs for isolation
- "EZ, huge buff to my workflow, got 3 or 4 chunks of features... for about 25 minutes of work"
- [Example PR](https://github.com/alexander-turner/TurnTrout.com/pull/462)

#### **Git Worktrees for Parallel Agents**
**Yoav Tzfati's worktree scripts** (Jan 2026):
- [GitHub: crazytieguy/worktree-scripts](https://github.com/crazytieguy/worktree-scripts)
- Allows parallel agents without conflicts
- [Kibitz](https://github.com/crazytieguy/kibitz): See git changes in terminal next to agent

### Research Workflows

#### **Literature Review with Claude Code** (Nathan Helm-Burger, Jan 2026)
1. Make project folder for lit review
2. Put draft project idea in folder
3. Start Claude Code
4. Tell it to create Python web scrape tools (use Exa Search API)
5. Run collection, debug as needed
6. Make Python script to convert PDFs to markdown
7. Ask Claude to find most relevant papers to cite
8. Check overlap with existing work

#### **Voice-to-Text Brainstorming** (Steven Veld, July 2025)
> "Just tried voice-to-text for a brainstorming session for the first time... damn its such a good workflow"

**Tools mentioned**:
- SuperWhisper (macOS)
- WhisperFlow
- [Sesame AI CSM](https://github.com/SesameAILabs/csm) - "really good voice model"
- Linux: [nerd-dictation](https://github.com/ideasman42/nerd-dictation) or [talkat](https://github.com/ronakrm/talkat)

### Writing Workflows

**Gap Identified** (Daniel Tan, April 2025):
> "I'm pretty curious about whether people have found a good AI assistant for writing. Currently I mostly use 4o and Claude 3.7 via the chat interface. It feels like there must be a better tool for this similar to Cursor but I havent found it."

**Emerging Options**:
- **OpenAI Prism** (Jan 2026): Jay Chooi posted "RIP overleaf" - [OpenAI announcement](https://openai.com/index/introducing-prism)
- **Cowork** (Jan 2026): "Claude Code for the rest of your work" - [Announcement](https://x.com/claudeai/status/2010805682434666759)
- **Kimi Agentic Slides** (Nov 2025): Designer-level visuals, fully editable PPTX export

**Other writing tools**:
- [RoastMyPost.org](https://www.roastmypost.org/) by Ozzie Gooen: LLM evaluators for blog posts/articles
  - Fact checking, link checking, spell checking, epistemic checking
  - Open-source and flexible

---

## ⚠️ Common Gotchas & Issues

### Claude Code Limitations

1. **Can't edit suggestions in VSCode extension** (Clément, July 2025):
   - Can edit preview but doesn't change what's applied when you press "yes"

2. **Multiple instances issue** (Nathan Hu, July 2025):
   - [GitHub issue #3625](https://github.com/anthropics/claude-code/issues/3625)

3. **MCP tools can't run in background** (Clément, Jan 2026):
   - "Super annoying if you want to give claude research MCP with tasks that take a long time"
   - No privileged channel to bump safety research issues

4. **Context management** (Yoav Tzfati, Sept 2025):
   - Positive: "It removes stale tool calls as it goes, letting you get much more work done per context window"
   - Can stay at 80% context usage for long tasks

### General Issues

1. **Providing too much context** (Steven Veld, July 2025):
   > "When I include a lot of context but still not near the context window limit, performance sometimes drops... as though the model is getting confused"

2. **AI slowdown for experienced devs** (Kai Williams, July 2025):
   - METR study: Experienced developers 19% SLOWER with AI tools
   - Question: "Is this mostly a skill issue?"
   - [Study link](https://metr.org/blog/2025-07-10-early-2025-ai-experienced-os-dev-study/)

3. **llms.txt multilingual duplication** (Clément, Nov 2025):
   - Same link mentioned 12 times in each language in Claude's and Cursor's llms.txt
   - Likely auto-generated for all subdomain pages

---

## 🛠️ MCP Servers & Extensions

### **Top 12 MCP Servers** (Philipp Schmidt, April 2025)
[LinkedIn post](https://www.linkedin.com/posts/philipp-schmid-a6a2bb196_here-are-my-top-12-mcp-servers-i-used-and-activity-7322898843463782400-2b8g)

1. **Python Code Interpreter**: Sandbox using Pyodide and Deno
2. **Web fetcher**: Playwright headless browser with JavaScript
3. **GitHub MCP server**: Seamless GitHub API integration
4. **Filesystem**: Read/write files, create/list/delete directories
5. **Google Drive**: List, read, search files; auto-export Google Workspace formats
6. **Fetch**: Convert HTML to markdown, chunked reading
7. **Markitdown**: Convert PDF, Office docs, HTML to Markdown
8. **Brave search**: Web searches and local business lookups
9. **Slack**: List channels, post messages, reply to threads
10. **Notion API**: Interact with Notion pages and databases
11. **Airbnb**: Search listings, get detailed info
12. **Arxiv**: Search and retrieve paper metadata

### Custom Tools

1. **webfetch2** (Dec 2025):
   - [GitHub: hibukki/webfetch2](https://github.com/hibukki/webfetch2)
   - Alternative to built-in web-fetch with fewer limitations

2. **Claude Code Usage Monitor** (Jan 2026):
   - [GitHub: Maciek-roboblog/Claude-Code-Usage-Monitor](https://github.com/Maciek-roboblog/Claude-Code-Usage-Monitor)
   - Track usage to avoid running out

3. **Code Simplifier Agent** (Jan 2026):
   - Open-sourced by Claude Code team
   - [Twitter announcement](https://x.com/bcherny/status/2009450715081789767)
   - Install: `claude plugin install code-simplifier`

---

## 📊 Tool Comparisons

### Claude Code vs Cursor

| Feature | Claude Code | Cursor |
|---------|-------------|--------|
| **Editing suggestions** | Can't edit in VSCode extension | Can edit suggestions |
| **Multi-instance** | Web UI supports separate VMs | Different approach |
| **Context management** | Auto-removes stale tool calls | - |
| **Test integration** | - | Question about Unvibe workflow |
| **Debugging** | - | Debug mode (Dec 2025) |
| **Agents** | - | Agents feature (Nov 2025) |

**Community Sentiment**:
- Cursor mentioned more for advanced workflows
- Claude Code preferred for research/exploration
- Some report Codex > Claude Code (unverified)

### Google Antigravity IDE
- Dan Hendrycks: "Gemini 3 is the largest leap in a long time"
- Raj planned to try "in the next few days" (Nov 2025)
- Limited follow-up discussion

### Other Tools Mentioned
- **Kimi K2**: Question about trying it (July 2025)
- **Manus AI**: Asked about (March 2025), no follow-up
- **Mem0**: [GitHub link](https://github.com/mem0ai/mem0) shared (July 2025)

---

## 🚀 Productivity Hacks

### Context Management

**Amanda Askell's wisdom** (Nov 2025):
> "People often err on the side of trying to make their prompts too succinct, even if the idea theyre trying to move from their own brain into the models brain is very complex. I have some >100 page prompts that I use pretty regularly."

[Twitter link](https://x.com/AmandaAskell/status/1986571451902927017)

### Visualization Tools

**Triskel** (Nov 2025): Library for making flowcharts with Claude - [GitHub](https://github.com/triskellib/triskel)

**OSGym** (Nov 2025): Tool for creating agentic computer-use rollouts - [GitHub](https://github.com/agiopen-org/osgym)

### Customization

**U0890UFK9KM** (Jan 2026): "Ive been customizing Claude Code lately, Ill gradually add some of those things in this thread"
- 5 raised_hands reactions
- Follow thread for customization tips

### Paper Review

**paperreview.ai** (Nov 2025):
- Achieves 0.4 correlation with human reviewers
- Same correlation as human reviewers with each other

---

## 📚 Notable Resources & Blog Posts

### Essential Reading

1. **[Groundhog AI / Cursor Vibecoding Meta](https://ghuntley.com/specs/)** (April 2025)
   - From design doc to code
   - "New meta when using Cursor"

2. **[How I force LLMs to generate correct code](https://www.lesswrong.com/posts/WNd3Lima4qrQ3fJEN/how-i-force-llms-to-generate-correct-code)** (March 2025)
   - Unvibe test-driven approach
   - Tree search for correctness

3. **[Reddit: 10 Claude skills that actually changed how I work](https://www.reddit.com/r/ClaudeAI/comments/1ojuqhm/10_claude_skills_that_actually_changed_how_i_work/)** (Oct 2025)

4. **[Reddit: Claude Code is a beast - tips from 6 months](https://www.reddit.com/r/ClaudeAI/comments/1oivjvm/claude_code_is_a_beast_tips_from_6_months_of/)** (Oct 2025)
   - Full-time SWE best practices

5. **[Tim Dettmers: 8 months using coding agents](https://x.com/Tim_Dettmers/status/2011061621389738251)** (Jan 2026)
   - Concepts, successes, failures in real settings

6. **[Cursor 2.0 commands from Cursor team](https://x.com/ericzakariasson/status/1983945740411138337)** (Oct 2025)
   - Shareable commands and rules

7. **[How AI is transforming work at Anthropic](https://www.anthropic.com/research/how-ai-is-transforming-work-at-anthropic)** (Dec 2025)
   - Internal usage insights

### Research-Specific

1. **[Concrete projects for improving AI safety research automation](https://www.lesswrong.com/posts/FqpAPC48CzAtvfx5C/concrete-projects-for-improving-current-technical-safety)** (July 2025)
   - Jacques Thibodeau mentored project
   - Indexable docs, sandboxed envs, benchmarks

2. **[METR: AI impact on OS developer productivity](https://metr.org/blog/2025-07-10-early-2025-ai-experienced-os-dev-study/)** (July 2025)
   - Experienced devs 19% slower with AI

3. **[Quentin Anthony: Dev slowdown causes/mitigation](https://x.com/quentinanthon15/status/1943948791775998069)** (July 2025)
   - Personal -38% AI-speedup experience

---

## 🔄 Evolution Over Time

### March 2025: Accessibility & Early Adoption
- Claude Code waitlist removed → mass adoption
- Voice coding interfaces emerging (CSM)
- Test-driven AI workflows discussions begin

### April-May 2025: Ecosystem Building
- MCP server ecosystem maturing (12+ servers in use)
- "Vibecoding" concept emerges
- Cursor advanced usage patterns shared

### July 2025: Reality Check
- METR study shows experienced devs slower with AI
- Community discusses skill development
- Context management strategies emerge

### October 2025: Major Tool Updates
- **Cursor 2.0**: New model, agents, shareable commands
- Claude Code web interface launched
- Petri open-sourced for AI auditing

### November-December 2025: Specialization
- Writing tools gap addressed (Cowork, Prism)
- Kimi Agentic Slides for presentations
- Debug mode in Cursor
- Seer library for interpretability research

### January 2026: Maturity & Best Practices
- Bloom released (complements Petri)
- Multiple scholars sharing advanced workflows
- Context7 and Superpowers plugins recommended
- Git worktrees for parallel agents
- Petri v2 improvements

### February 2026: Integration & Optimization
- Alex Turner: massive productivity gains with web UI
- Multiple instances + VMs becoming standard
- Community asking for comprehensive summaries

---

## 🎯 Action Items for New Users

### Immediate Setup (Day 1)
1. **Install Claude Code**: `npm install -g @anthropic-ai/claude-code`
2. **Add plugins**:
   - `/plugins` → install context7
   - `/plugins` → install superpowers (use brainstorming skill)
3. **Set up usage monitoring**: [Claude Code Usage Monitor](https://github.com/Maciek-roboblog/Claude-Code-Usage-Monitor)

### Week 1: Core Workflows
1. **Read essential guides**:
   - [Reddit: Claude Code best practices](https://www.reddit.com/r/ClaudeAI/comments/1oivjvm/claude_code_is_a_beast_tips_from_6_months_of/)
   - [LessWrong: Force correctness](https://www.lesswrong.com/posts/WNd3Lima4qrQ3fJEN/how-i-force-llms-to-generate-correct-code)
2. **Try voice-to-text** for brainstorming (SuperWhisper on Mac)
3. **Experiment with web UI** for multiple instances

### Month 1: Advanced Setup
1. **Install MCP servers** (start with Python interpreter, GitHub, filesystem)
2. **Set up git worktrees** for parallel agents
3. **Try test-driven workflow** with Unvibe approach
4. **Explore Seer** if doing interpretability research

### Ongoing Optimization
- **Read Amanda Askell's advice**: Don't over-optimize for brevity
- **Join #ai-tools Slack**: Learn from community
- **Track METR insights**: Understand when AI helps vs hinders
- **Experiment with Petri/Bloom**: For model auditing research

---

## 🔍 Open Questions & Gaps

1. **Writing workflows**: Still no consensus on best AI writing assistant (as of Feb 2026)
2. **Cursor + Unvibe integration**: How to implement test-driven tree search?
3. **MCP background tasks**: Claude Code limitation for long-running research tasks
4. **Multi-instance best practices**: Emerging but not fully documented
5. **AI slowdown mitigation**: How experienced devs can avoid productivity loss

---

## 📞 Key Contributors to Follow

- **Jacques Thibodeau** (thibo.jacques): Extensive automation work, research projects
- **Nathan Helm-Burger** (nathan): Multiple tool recommendations, lit review workflows
- **Yoav Tzfati** (yoav.tzfati): Git worktrees, usage monitoring tools
- **Alex Turner** (jobeal2): Web UI workflows, multiple instances
- **Daniel Tan** (dtch009): Experiment workflows, MCP servers
- **Yonatan Cale** (yonatan.cale): Plugin recommendations (context7, superpowers)
- **Lovkush Agarwal** (lovkush): Petri, Bloom, Seer, Cursor updates

---

*Last updated: February 2026*
*Source: MATS #ai-tools Slack channel (full year analysis)*
*Total messages analyzed: 80+ over 12 months*

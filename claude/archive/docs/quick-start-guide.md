# Quick Start Guide - AI Research Template

## 🚀 5-Minute Setup

### 1. Clone and Merge Template
```bash
# Clone this template
git clone [template-repo] ai-research-template
cd ai-research-template

# Merge with your existing research code
cd [your-research-project]
git remote add template [path-to-template]
git fetch template
git merge template/main --allow-unrelated-histories
```

### 2. Start Claude Code
```bash
claude
```

### 3. Run Setup Wizard
```
/setup
```

This will guide you through:
- Integrating your codebase
- Creating documentation
- Building custom commands
- Setting up verification

## 🎯 Essential Commands

| Command | Purpose | Example |
|---------|---------|---------|
| `/setup` | Interactive setup wizard | `/setup` |
| `/crud-claude-commands` | Create custom commands | `/crud-claude-commands create run-experiment` |
| `/page` | Save session state | `/page "checkpoint-1"` |
| `/plan-with-context` | Smart planning | `/plan-with-context "implement feature X"` |
| `/parallel-analysis-example` | Example multi-agent pattern | See command for adaptation guide |

## 📝 Specification-Driven Workflow

### 1. Copy the Spec Template
```bash
cp specs/EXAMPLE_RESEARCH_SPEC.md specs/my-experiment.md
```

### 2. Fill Out Key Sections
- Problem Statement
- Success Criteria  
- Technical Approach
- Implementation Plan
- Self-Validation

### 3. Use AI to Help Draft
```
> Read specs/my-experiment.md
> Help me fill out the Technical Approach section based on [research context]
```

### 4. Implement Based on Spec
```
> Implement Phase 1 from specs/my-experiment.md
```

## 🔄 Creating Custom Commands

After running `/setup`, create commands for your workflow:

```
# For experiment automation
/crud-claude-commands create run-experiment

# For analysis workflows  
/crud-claude-commands create analyze-results

# For common debugging
/crud-claude-commands create debug-training
```

## 🪝 Active Safety Features

The template includes safety hooks:
- **Mock Data Validation** - Prevents synthetic data in real experiments
- **Auto-Commit** - Saves work when Claude stops
- **Python Formatting** - Auto-formats code

## 💡 Context Management Tips

### Check Context Usage
- Monitor usage to avoid hitting limits
- Use `/page` when approaching 70% capacity

### Extended Thinking
For complex problems, trigger deeper reasoning:
- "think step by step" - Basic reasoning
- "think deeply" - Thorough analysis  
- "think harder" - Complex problem solving
- "ultrathink" - Maximum reasoning depth

## 📁 Key Directories

- **ai_docs/** - Your AI-optimized documentation
- **specs/** - Experiment specifications
- **experiments/** - Results and logs
- **scripts/** - Automation scripts
- **utils/** - Python utilities

## 🆘 Troubleshooting

### Commands Not Working
```bash
# Restart Claude Code or check command exists
ls .claude/commands/
```

### Context Filling Quickly
```bash
# Save and resume
/page "checkpoint"
claude --resume
```

## 🎉 Next Steps

1. Complete the `/setup` wizard
2. Create your first specification
3. Build a custom command for your most common task
4. Start implementing!

Remember: The goal is to make AI agents effective research assistants that understand your specific domain and workflow.
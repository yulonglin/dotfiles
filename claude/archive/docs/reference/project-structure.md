# Project Structure

This document describes the organization of the AI Safety Research Template.

## Directory Layout

```
ais-agent-scripts/
├── .claude/                    # Claude Code configuration
│   ├── commands/              # Custom slash commands
│   │   ├── analyze-function.md
│   │   ├── crud-claude-commands.md
│   │   ├── multi-mind.md
│   │   ├── page.md
│   │   ├── plan-with-context.md
│   │   ├── search-prompts.md
│   │   └── spec-driven.md
│   └── scripts/               # Supporting scripts for commands
│       └── extract-claude-session.py
│
├── docs/                      # Documentation
│   ├── guides/               # User guides and tutorials
│   │   ├── claude-code-search-best-practices.md
│   │   ├── claude-conversation-search-guide.md
│   │   ├── claude-custom-commands.md
│   │   ├── claude-hooks-configuration.md
│   │   ├── gemini-integration.md
│   │   └── improvements-summary.md
│   ├── reference/            # Reference documentation
│   │   └── project-structure.md (this file)
│   ├── templates/            # Document templates
│   │   ├── issue-template.md
│   │   ├── plan-template.md
│   │   ├── specification-template.md
│   │   └── task-template.md
│   ├── specs/                # Specifications (created by users)
│   ├── plans/                # Implementation plans (created by users)
│   └── todo.md               # Project todo list
│
├── examples/                  # Usage examples
│   ├── specification-workflow.md
│   └── using-custom-commands.md
│
├── scripts/                   # Utility scripts
│   ├── setup.sh              # Full project setup
│   ├── quick-integrate.sh    # Quick command installation
│   └── run-spec-tests.sh     # Specification testing runner
│
├── utils/                     # Python utilities
│   ├── context_analyzer.py   # Intelligent file selection
│   ├── session_manager.py    # Session checkpoint management
│   ├── spec_validator.py     # Specification validation & test generation
│   ├── task_manager.py       # Task creation and tracking
│   └── todo_manager.py       # Todo list management
│
├── tasks/                     # Task files (created by task_manager.py)
│   └── .gitkeep
│
├── tests/                     # Test files (generated from specs)
│   └── .gitkeep
│
├── issues/                    # Issue tracking files
│   └── .gitkeep
│
├── CLAUDE.md                  # Claude's memory file
├── README.md                  # Project documentation
└── .gitignore                 # Git ignore rules
```

## Key Directories

### `.claude/`
Contains Claude Code specific configuration:
- **commands/**: Custom slash commands in markdown format
- **scripts/**: Python scripts that support the commands

### `docs/`
All documentation organized by type:
- **guides/**: How-to guides and tutorials
- **reference/**: Technical reference documentation  
- **templates/**: Reusable document templates
- **specs/**: User-created specifications
- **plans/**: User-created implementation plans

### `scripts/`
Shell scripts for setup and automation:
- **setup.sh**: Interactive setup for full integration
- **quick-integrate.sh**: Fast command-only installation
- **run-spec-tests.sh**: Automated spec validation and testing

### `utils/`
Python utilities for advanced functionality:
- **context_analyzer.py**: Analyzes codebases to select relevant files
- **session_manager.py**: Saves and restores research sessions
- **spec_validator.py**: Validates specifications and generates tests
- **task_manager.py**: Manages tasks with why/what/how structure
- **todo_manager.py**: Converts between Claude and markdown todos

### User-Created Directories
These directories store files created during research:
- **tasks/**: Task management files
- **tests/**: Generated test files
- **issues/**: Issue tracking documents
- **docs/specs/**: Detailed specifications
- **docs/plans/**: Implementation plans

## File Naming Conventions

- Specifications: `SPEC-YYYY-MM-DD-feature-name.md`
- Tasks: `task-YYYY-MM-DD-NNN-title.md`
- Plans: `PLAN-YYYY-MM-DD-feature-name.md`
- Tests: `test_feature_name.py` (generated from specs)

## Best Practices

1. **Keep user files separate**: User-created content goes in designated directories
2. **Use templates**: Start with templates for consistency
3. **Follow naming conventions**: Makes files easy to find and sort
4. **Document as you go**: Update plans and specs during implementation
5. **Clean up regularly**: Remove temporary files and old backups
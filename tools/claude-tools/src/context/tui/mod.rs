pub mod state;
pub mod theme;

use crossterm::event::{self, Event, KeyCode, KeyEventKind};
use crossterm::terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen};
use crossterm::ExecutableCommand;
use ratatui::prelude::*;
use ratatui::widgets::{Block, Borders, Paragraph};

use state::AppState;
use crate::context::{builder, profiles, registry, settings};

pub fn run() -> Result<(), Box<dyn std::error::Error>> {
    // Load data
    let (_base, profile_defs) = profiles::load_profiles()?;
    let active = settings::load_context_yaml()?
        .map(|(p, _, _)| p)
        .unwrap_or_default();

    let mut state = AppState::new(&profile_defs, &active);

    // Setup terminal
    enable_raw_mode()?;
    std::io::stdout().execute(EnterAlternateScreen)?;
    let backend = CrosstermBackend::new(std::io::stdout());
    let mut terminal = Terminal::new(backend)?;

    // Main loop
    loop {
        terminal.draw(|frame| view(frame, &state))?;

        if let Event::Key(key) = event::read()? {
            if key.kind != KeyEventKind::Press {
                continue;
            }
            match key.code {
                KeyCode::Char('q') | KeyCode::Esc => {
                    state.quit = true;
                    break;
                }
                KeyCode::Enter => {
                    state.apply = true;
                    break;
                }
                KeyCode::Up | KeyCode::Char('k') => state.move_up(),
                KeyCode::Down | KeyCode::Char('j') => state.move_down(),
                KeyCode::Char(' ') => state.toggle_current(),
                KeyCode::Char('a') => state.select_all(),
                KeyCode::Char('n') => state.select_none(),
                _ => {}
            }
        }
    }

    // Restore terminal
    disable_raw_mode()?;
    std::io::stdout().execute(LeaveAlternateScreen)?;

    // Apply if user pressed enter
    if state.apply && state.is_modified() {
        let selected = state.selected_profile_names();
        let reg = registry::load_registry()?;
        let (base, profile_defs) = profiles::load_profiles()?;
        let enabled = builder::build_plugins(&reg, &base, &profile_defs, &selected, &[], &[])?;
        settings::apply_to_settings(&enabled)?;
        settings::write_context_yaml(&selected, &[], &[])?;

        let mut on: Vec<&str> = enabled
            .iter()
            .filter(|(_, v)| **v)
            .map(|(k, _)| k.split('@').next().unwrap_or(k.as_str()))
            .collect();
        on.sort();
        println!("\x1b[0;32mApplied:\x1b[0m {}", selected.join(", "));
        println!("\x1b[0;32mEnabled:\x1b[0m {}", on.join(", "));
        println!("\x1b[0;33mRestart Claude Code to apply changes.\x1b[0m");
    } else if state.apply {
        println!("No changes.");
    }

    Ok(())
}

fn view(frame: &mut Frame, state: &AppState) {
    let area = frame.area();
    let mut lines: Vec<Line> = Vec::new();

    // Header: Active profiles
    let active: Vec<&str> = state
        .profiles
        .iter()
        .filter(|p| p.enabled)
        .map(|p| p.name.as_str())
        .collect();
    let header_text = if active.is_empty() {
        "(none)".to_string()
    } else {
        active.join(", ")
    };
    let mut header_line = vec![
        Span::styled("  Active: ", theme::header()),
        Span::styled(header_text, Style::default().fg(theme::BLUE)),
    ];
    if state.is_modified() {
        header_line.push(Span::styled("  [modified]", theme::modified_indicator()));
    }
    lines.push(Line::from(header_line));
    lines.push(Line::from(""));

    // Profile list
    for (i, profile) in state.profiles.iter().enumerate() {
        let is_cursor = i == state.cursor;
        let symbol = if profile.enabled {
            theme::FILLED
        } else {
            theme::EMPTY
        };

        let name_style = if is_cursor {
            theme::cursor()
        } else if profile.enabled {
            theme::selected()
        } else {
            theme::unselected()
        };

        lines.push(Line::from(vec![
            Span::raw("  "),
            Span::styled(symbol, name_style),
            Span::raw(" "),
            Span::styled(format!("{:<12}", profile.name), name_style),
            Span::styled(&*profile.comment, theme::hint()),
        ]));

        // Expand plugins for highlighted profile
        if is_cursor && !profile.plugins.is_empty() {
            for (j, plugin) in profile.plugins.iter().enumerate() {
                let branch = if j == profile.plugins.len() - 1 {
                    theme::BRANCH_LAST
                } else {
                    theme::BRANCH
                };
                lines.push(Line::from(vec![
                    Span::raw("    "),
                    Span::styled(branch, theme::tree_branch()),
                    Span::styled(format!(" {}", plugin), theme::tree_branch()),
                ]));
            }
        }
    }

    // Footer
    lines.push(Line::from(""));
    lines.push(Line::from(vec![
        Span::styled("  space", theme::hint()),
        Span::raw(": toggle  "),
        Span::styled("enter", theme::hint()),
        Span::raw(": apply  "),
        Span::styled("q", theme::hint()),
        Span::raw(": quit"),
    ]));

    let block = Block::default()
        .title(theme::TITLE)
        .borders(Borders::ALL)
        .border_style(Style::default().fg(theme::GRAY));

    let paragraph = Paragraph::new(lines).block(block);
    frame.render_widget(paragraph, area);
}

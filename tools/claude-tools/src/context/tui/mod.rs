pub mod state;
pub mod theme;

use crossterm::event::{self, Event, KeyCode, KeyEventKind};
use crossterm::terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen};
use crossterm::ExecutableCommand;
use ratatui::prelude::*;
use ratatui::widgets::{Block, Borders, Paragraph};

use state::{AppState, Override, View};
use crate::context::{builder, display, profiles, registry, settings, sync};

pub fn run() -> Result<(), Box<dyn std::error::Error>> {
    // Load data before entering TUI
    let reg = registry::load_registry()?;
    let (base, profile_defs) = profiles::load_profiles()?;
    let (active_profiles, active_enable, active_disable) = settings::load_context_yaml()?
        .unwrap_or_default();

    if profile_defs.is_empty() {
        println!("No profiles defined in profiles.yaml");
        return Ok(());
    }

    let mut state = AppState::new(&reg, &base, &profile_defs, &active_profiles, &active_enable, &active_disable);

    loop {
        // Setup terminal
        enable_raw_mode()?;
        std::io::stdout().execute(EnterAlternateScreen)?;

        // Run the main loop, ensuring terminal is always restored
        let result = run_loop(&mut state);

        // Always restore terminal, even on error
        let _ = disable_raw_mode();
        let _ = std::io::stdout().execute(LeaveAlternateScreen);

        // Propagate any error from the loop
        result?;

        if state.sync {
            state.sync = false;
            // Run sync outside of TUI (it spawns subprocesses and prints output)
            println!();
            sync::run(true, false)?;
            println!("\nPress any key to return to TUI...");
            // Re-enable raw mode briefly to capture a keypress
            enable_raw_mode()?;
            let _ = event::read();
            let _ = disable_raw_mode();

            // Reload data after sync (new plugins may have been installed)
            let reg = registry::load_registry()?;
            let (base, profile_defs) = profiles::load_profiles()?;
            let selected = state.selected_profile_names();
            let enable = state.enable_overrides();
            let disable = state.disable_overrides();
            state = AppState::new(&reg, &base, &profile_defs, &selected, &enable, &disable);
            continue;
        }

        break;
    }

    // Apply if user pressed enter
    if state.apply {
        let selected = state.selected_profile_names();
        let enable = state.enable_overrides();
        let disable = state.disable_overrides();

        if selected.is_empty() {
            println!("No profiles selected. Use --clean to remove context config.");
            return Ok(());
        }
        if !state.is_modified() {
            println!("No changes.");
            return Ok(());
        }

        let reg = registry::load_registry()?;
        let (base, profile_defs) = profiles::load_profiles()?;
        let enabled = builder::build_plugins(&reg, &base, &profile_defs, &selected, &enable, &disable)?;
        settings::apply_to_settings(&enabled)?;
        settings::write_context_yaml(&selected, &enable, &disable)?;
        display::print_apply_summary(&selected, &enabled);
    }

    Ok(())
}

fn run_loop(state: &mut AppState) -> Result<(), Box<dyn std::error::Error>> {
    let backend = CrosstermBackend::new(std::io::stdout());
    let mut terminal = Terminal::new(backend)?;

    loop {
        terminal.draw(|frame| view(frame, state))?;

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
                KeyCode::Tab | KeyCode::BackTab | KeyCode::Left | KeyCode::Right
                | KeyCode::Char('h') | KeyCode::Char('l') => state.switch_view(),
                KeyCode::Up | KeyCode::Char('k') => state.move_up(),
                KeyCode::Down | KeyCode::Char('j') => state.move_down(),
                KeyCode::Char(' ') => state.toggle_current(),
                KeyCode::Char('a') => state.select_all(),
                KeyCode::Char('n') => state.select_none(),
                KeyCode::Char('s') => {
                    state.sync = true;
                    break;
                }
                _ => {}
            }
        }
    }

    Ok(())
}

fn view(frame: &mut Frame, state: &AppState) {
    let area = frame.area();
    let mut lines: Vec<Line> = Vec::new();

    // Tab bar
    let profiles_tab = if state.view == View::Profiles {
        Span::styled(" Profiles ", theme::tab_active())
    } else {
        Span::styled(" Profiles ", theme::tab_inactive())
    };
    let plugins_tab = if state.view == View::Plugins {
        Span::styled(" Plugins ", theme::tab_active())
    } else {
        Span::styled(" Plugins ", theme::tab_inactive())
    };
    lines.push(Line::from(vec![
        Span::raw("  "),
        profiles_tab,
        Span::styled("  │  ", theme::hint()),
        plugins_tab,
    ]));
    lines.push(Line::from(""));

    // Status header
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
    let overrides = state.override_count();
    if overrides > 0 {
        header_line.push(Span::styled(
            format!("  ({} override{})", overrides, if overrides == 1 { "" } else { "s" }),
            theme::override_on(),
        ));
    }
    if state.is_modified() {
        header_line.push(Span::styled("  [modified]", theme::modified_indicator()));
    }
    lines.push(Line::from(header_line));
    lines.push(Line::from(""));

    match state.view {
        View::Profiles => render_profiles(&mut lines, state),
        View::Plugins => render_plugins(&mut lines, state),
    }

    // Footer
    lines.push(Line::from(""));
    let mut footer = vec![
        Span::styled("  space", theme::hint()),
        Span::raw(": toggle  "),
        Span::styled("tab", theme::hint()),
        Span::raw(": switch view  "),
        Span::styled("s", theme::hint()),
        Span::raw(": sync  "),
    ];
    if state.view == View::Profiles {
        footer.extend_from_slice(&[
            Span::styled("a", theme::hint()),
            Span::raw(": all  "),
            Span::styled("n", theme::hint()),
            Span::raw(": none  "),
        ]);
    } else {
        footer.extend_from_slice(&[
            Span::styled("n", theme::hint()),
            Span::raw(": clear overrides  "),
        ]);
    }
    footer.extend_from_slice(&[
        Span::styled("enter", theme::hint()),
        Span::raw(": apply  "),
        Span::styled("q", theme::hint()),
        Span::raw(": quit"),
    ]);
    lines.push(Line::from(footer));

    let block = Block::default()
        .title(theme::TITLE)
        .borders(Borders::ALL)
        .border_style(Style::default().fg(theme::GRAY));

    let paragraph = Paragraph::new(lines).block(block);
    frame.render_widget(paragraph, area);
}

fn render_profiles<'a>(lines: &mut Vec<Line<'a>>, state: &'a AppState) {
    for (i, profile) in state.profiles.iter().enumerate() {
        let is_cursor = state.view == View::Profiles && i == state.profile_cursor;
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
            Span::styled(format!("{:<14}", profile.name), name_style),
            Span::styled(profile.comment.as_str(), theme::hint()),
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
}

fn render_plugins<'a>(lines: &mut Vec<Line<'a>>, state: &'a AppState) {
    for (i, plugin) in state.plugins.iter().enumerate() {
        let is_cursor = state.view == View::Plugins && i == state.plugin_cursor;

        let (symbol, sym_style) = match plugin.override_state {
            Override::ForceOn => (theme::OVERRIDE_ON, theme::override_on()),
            Override::ForceOff => (theme::OVERRIDE_OFF, theme::override_off()),
            Override::Inherit if plugin.effective() => (theme::FILLED, theme::selected()),
            Override::Inherit => (theme::EMPTY, theme::unselected()),
        };

        let name_style = if is_cursor {
            theme::cursor()
        } else {
            sym_style
        };

        let source = plugin.source();
        let mut spans = vec![
            Span::raw("  "),
            Span::styled(symbol, if is_cursor { theme::cursor() } else { sym_style }),
            Span::raw(" "),
            Span::styled(format!("{:<24}", plugin.name), name_style),
        ];
        if !source.is_empty() {
            spans.push(Span::styled(source, theme::hint()));
        }

        lines.push(Line::from(spans));
    }
}

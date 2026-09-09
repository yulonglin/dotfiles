pub mod state;

use std::io::{self, BufRead};
use std::time::Duration;

use crossterm::event::{self, Event, KeyCode, KeyEventKind};
use crossterm::terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen};
use crossterm::ExecutableCommand;
use ratatui::backend::CrosstermBackend;
use ratatui::prelude::*;
use ratatui::Terminal;
use ratatui::widgets::{Block, Borders, Paragraph};

use state::{AppState, ListItem};
use crate::context::tui::theme;

pub fn run(args: Vec<String>) -> Result<(), Box<dyn std::error::Error>> {
    // Flags: --title <text>, --single (Enter picks the cursor row; no toggling)
    let mut title = "Select components".to_string();
    let mut single = false;
    let mut i = 1; // args[0] is "claude-tools-select"
    while i < args.len() {
        if args[i] == "--title" {
            if i + 1 < args.len() {
                title = args[i + 1].clone();
                i += 2;
            } else {
                i += 1;
            }
        } else if args[i] == "--single" {
            single = true;
            i += 1;
        } else {
            i += 1;
        }
    }

    // Read items from stdin: group|name|description|checked
    let stdin = io::stdin();
    let mut items: Vec<ListItem> = Vec::new();
    let mut last_group: Option<String> = None;

    for line in stdin.lock().lines() {
        let line = line?;
        if line.trim().is_empty() { continue; }

        let parts: Vec<&str> = line.splitn(4, '|').collect();
        if parts.len() < 4 {
            continue;
        }
        let group = parts[0].trim().to_string();
        let name = parts[1].trim().to_string();
        let description = parts[2].trim().to_string();
        let checked = parts[3].trim() == "true";

        // Insert group header if this is a new group
        if last_group.as_deref() != Some(&group) {
            items.push(ListItem::GroupHeader { name: group.clone() });
            last_group = Some(group);
        }

        items.push(ListItem::Component { name, description, selected: checked });
    }

    if items.is_empty() {
        return Ok(());
    }

    let mut state = AppState::new(items, single);

    // Render TUI to stderr so stdout stays clean for selected-names output.
    // This is critical: deploy.sh captures our stdout in result=$(...) and
    // uses each line as a variable name — any escape codes there cause errors.
    enable_raw_mode()?;
    io::stderr().execute(EnterAlternateScreen)?;

    let result = run_loop(&mut state, &title);

    let _ = disable_raw_mode();
    let _ = io::stderr().execute(LeaveAlternateScreen);

    result?;

    if state.cancelled {
        std::process::exit(1);
    }

    // Print selected names to stdout (clean, no escape codes)
    for name in state.selected_names() {
        println!("{}", name);
    }

    Ok(())
}

fn run_loop(state: &mut AppState, title: &str) -> Result<(), Box<dyn std::error::Error>> {
    // Backend on stderr; raw mode + alternate screen are managed by the caller.
    let backend = CrosstermBackend::new(std::io::stderr());
    let mut terminal = Terminal::new(backend)?;

    // Slow idle tick: forces a full repaint to self-heal mosh smearing while idle.
    // 1.5 s is infrequent enough that it won't visibly strobe even over a slow link.
    const IDLE_TICK: Duration = Duration::from_millis(1500);


    loop {
        terminal.draw(|f| render(f, state, title))?;

        if event::poll(IDLE_TICK)? {
            match event::read()? {
                Event::Key(key) => {
                    if key.kind != KeyEventKind::Press { continue; }
                    match key.code {
                        KeyCode::Char('q') | KeyCode::Esc => { state.cancelled = true; break; }
                        KeyCode::Enter => {
                            if state.single { state.select_cursor_only(); }
                            state.confirmed = true;
                            break;
                        }
                        // Single mode: space is a forgiving alias for Enter.
                        KeyCode::Char(' ') if state.single => {
                            state.select_cursor_only();
                            state.confirmed = true;
                            break;
                        }
                        KeyCode::Char(' ') => state.toggle(),
                        KeyCode::Down | KeyCode::Char('j') => state.move_down(),
                        KeyCode::Up | KeyCode::Char('k') => state.move_up(),
                        // Ctrl-L: force full repaint to heal mosh/terminal desync
                        KeyCode::Char('l') if key.modifiers.contains(crossterm::event::KeyModifiers::CONTROL) => {
                            terminal.clear()?;
                        }
                        _ => {}
                    }
                }
                // Resize: clear and redraw immediately to heal desynced cells
                Event::Resize(..) => {
                    terminal.clear()?;
                }
                _ => {}
            }
        }
        // Idle tick: redraw (the loop continues, terminal.draw fires at top)
    }

    Ok(())
}

fn render(f: &mut ratatui::Frame, state: &AppState, title: &str) {
    let area = f.area();

    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(3),
            Constraint::Min(1),
            Constraint::Length(2),
        ])
        .split(area);

    // Header
    let hints = if state.single {
        vec![
            Span::styled(" j/k ", theme::hint()),
            Span::raw("navigate  "),
            Span::styled("enter ", theme::hint()),
            Span::raw("select  "),
            Span::styled("q ", theme::hint()),
            Span::raw("cancel  "),
            Span::styled("ctrl-l ", theme::hint()),
            Span::raw("repaint"),
        ]
    } else {
        vec![
            Span::styled(" j/k ", theme::hint()),
            Span::raw("navigate  "),
            Span::styled("space ", theme::hint()),
            Span::raw("toggle  "),
            Span::styled("enter ", theme::hint()),
            Span::raw("confirm  "),
            Span::styled("q ", theme::hint()),
            Span::raw("cancel  "),
            Span::styled("ctrl-l ", theme::hint()),
            Span::raw("repaint"),
        ]
    };
    let header = Paragraph::new(vec![
        Line::from(vec![
            Span::styled(format!(" {} ", title), theme::header()),
        ]),
        Line::from(hints),
    ]).block(Block::default().borders(Borders::BOTTOM));
    f.render_widget(header, chunks[0]);

    // List area
    let list_area = chunks[1];
    let mut lines: Vec<Line> = Vec::new();

    let visible_height = list_area.height as usize;
    let scroll_offset = if state.cursor > visible_height / 2 {
        state.cursor.saturating_sub(visible_height / 2)
    } else {
        0
    };

    for (i, item) in state.items.iter().enumerate().skip(scroll_offset).take(visible_height) {
        match item {
            ListItem::GroupHeader { name } => {
                lines.push(Line::from(vec![
                    Span::styled(format!("  {} ", name), theme::header()),
                ]));
            }
            ListItem::Component { name, description, selected } => {
                let is_cursor = i == state.cursor;
                let check_style = if *selected {
                    theme::selected()
                } else {
                    Style::default().fg(theme::GRAY)
                };
                let check_char = if *selected { "✓" } else { " " };
                let cursor_char = if is_cursor { ">" } else { " " };
                let cursor_style = if is_cursor { theme::cursor() } else { Style::default() };
                let name_style = if is_cursor { theme::cursor() } else { theme::unselected() };

                let mut spans = vec![Span::styled(format!(" {} ", cursor_char), cursor_style)];
                // Single mode has no checkbox: the cursor is the selection.
                if !state.single {
                    spans.push(Span::styled("[", check_style));
                    spans.push(Span::styled(check_char, check_style));
                    spans.push(Span::styled("] ", check_style));
                }
                spans.push(Span::styled(format!("{:<24}", name), name_style));
                spans.push(Span::styled(description.to_string(), theme::hint()));
                lines.push(Line::from(spans));
            }
        }
    }

    let list = Paragraph::new(lines);
    f.render_widget(list, list_area);

    // Footer
    let footer_text = if state.single {
        "  enter picks the highlighted row".to_string()
    } else {
        format!("  {} selected", state.selected_count())
    };
    let footer = Paragraph::new(Line::from(vec![
        Span::styled(footer_text, Style::default().fg(theme::GREEN)),
    ])).block(Block::default().borders(Borders::TOP));
    f.render_widget(footer, chunks[2]);
}

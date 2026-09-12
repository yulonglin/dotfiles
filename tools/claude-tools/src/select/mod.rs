pub mod state;

use std::io::{self, BufRead};
use std::time::{Duration, Instant};

use crossterm::event::{self, Event, KeyCode, KeyEventKind};
use crossterm::terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen};
use crossterm::ExecutableCommand;
use ratatui::backend::CrosstermBackend;
use ratatui::prelude::*;
use ratatui::Terminal;
use ratatui::widgets::{Block, Borders, Paragraph};

use state::{AppState, ListItem};
use crate::context::tui::theme;

// Exit codes are the contract with scripts/shared/helpers.sh:
//   0  confirmed — selected names on stdout, one per line (possibly none)
//   1  cancelled (q / Esc)
//   2  usage or contract error — message on stderr, nothing drawn
//   3  idle deadline passed with no keystroke — nothing on stdout
pub const EXIT_CANCELLED: i32 = 1;
pub const EXIT_USAGE: i32 = 2;
pub const EXIT_IDLE: i32 = 3;

const USAGE: &str = "usage: claude-tools select --items FILE [--title TEXT] [--idle-timeout SECS]";

fn usage_error(msg: &str) -> ! {
    eprintln!("claude-tools select: {msg}");
    eprintln!("{USAGE}");
    std::process::exit(EXIT_USAGE);
}

pub fn run(args: Vec<String>) -> Result<(), Box<dyn std::error::Error>> {
    // Strict parsing. From 2026-06-21 to 2026-09-04 this loop ignored any
    // flag it did not know, so when a merge dropped --items the shell kept
    // passing it, the binary silently read its items from the terminal
    // instead, drew nothing, and waited for keystrokes nobody knew to type.
    // An unknown flag is now a loud exit 2 within a millisecond.
    let mut title = "Select components".to_string();
    let mut items_file: Option<String> = None;
    let mut idle_timeout: Option<Duration> = None;
    let mut i = 1; // args[0] is "claude-tools-select"
    while i < args.len() {
        let value = |flag: &str| -> String {
            if i + 1 >= args.len() {
                usage_error(&format!("{flag} needs a value"));
            }
            args[i + 1].clone()
        };
        match args[i].as_str() {
            "--title" => { title = value("--title"); i += 2; }
            "--items" => { items_file = Some(value("--items")); i += 2; }
            "--idle-timeout" => {
                let secs: u64 = value("--idle-timeout").parse()
                    .unwrap_or_else(|_| usage_error("--idle-timeout wants whole seconds"));
                idle_timeout = Some(Duration::from_secs(secs));
                i += 2;
            }
            "-h" | "--help" => { println!("{USAGE}"); return Ok(()); }
            other => usage_error(&format!("unknown argument {other:?}")),
        }
    }

    // Items come from --items FILE: group|name|description|checked.
    //
    // stdin stays attached to the controlling terminal for keyboard input.
    // Piping the list in on stdin makes fd 0 a pipe, which forces crossterm
    // onto its /dev/tty fallback — fragile, and it fails outright on some
    // terminals ("Failed to initialize input reader"). Reading items from a
    // terminal is therefore never right: it blocks with nothing drawn, which
    // is exactly the 2026-09-04 stall. Refuse it rather than wait.
    let raw: Box<dyn BufRead> = match &items_file {
        Some(path) => Box::new(io::BufReader::new(std::fs::File::open(path)?)),
        None if io::IsTerminal::is_terminal(&io::stdin()) => {
            usage_error("no --items FILE and stdin is a terminal; refusing to read items from the keyboard");
        }
        None => Box::new(io::stdin().lock()),
    };
    let mut items: Vec<ListItem> = Vec::new();
    let mut last_group: Option<String> = None;

    for line in raw.lines() {
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

    let mut state = AppState::new(items);

    // Render TUI to stderr so stdout stays clean for selected-names output.
    // This is critical: deploy.sh captures our stdout in result=$(...) and
    // uses each line as a variable name — any escape codes there cause errors.
    enable_raw_mode()?;
    io::stderr().execute(EnterAlternateScreen)?;

    let result = run_loop(&mut state, &title, idle_timeout);

    let _ = disable_raw_mode();
    let _ = io::stderr().execute(LeaveAlternateScreen);

    result?;

    if state.cancelled {
        std::process::exit(EXIT_CANCELLED);
    }
    if state.idle {
        // The deadline lives here, not only in the shell's `timeout` wrapper:
        // macOS has no timeout(1) until install.sh has installed coreutils, so
        // the first run on a fresh Mac is exactly the one that needs it.
        eprintln!("claude-tools select: no keystroke for {}s — leaving the selection as it was",
            idle_timeout.map(|d| d.as_secs()).unwrap_or(0));
        std::process::exit(EXIT_IDLE);
    }

    // Print selected names to stdout (clean, no escape codes)
    for name in state.selected_names() {
        println!("{}", name);
    }

    Ok(())
}

fn run_loop(state: &mut AppState, title: &str, idle_timeout: Option<Duration>) -> Result<(), Box<dyn std::error::Error>> {
    // Backend on stderr; raw mode + alternate screen are managed by the caller.
    let backend = CrosstermBackend::new(std::io::stderr());
    let mut terminal = Terminal::new(backend)?;

    // Slow idle tick: forces a full repaint to self-heal mosh smearing while idle.
    // 1.5 s is infrequent enough that it won't visibly strobe even over a slow link.
    const IDLE_TICK: Duration = Duration::from_millis(1500);

    // The first draw happens before the first read, always: a menu that can
    // wait must be visible while it waits.
    let mut last_key = Instant::now();

    loop {
        terminal.draw(|f| render(f, state, title))?;

        if let Some(limit) = idle_timeout {
            if last_key.elapsed() >= limit {
                state.idle = true;
                break;
            }
        }

        if event::poll(IDLE_TICK)? {
            match event::read()? {
                Event::Key(key) => {
                    if key.kind != KeyEventKind::Press { continue; }
                    last_key = Instant::now();
                    match key.code {
                        KeyCode::Char('q') | KeyCode::Esc => { state.cancelled = true; break; }
                        KeyCode::Enter => { state.confirmed = true; break; }
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
    let header = Paragraph::new(vec![
        Line::from(vec![
            Span::styled(format!(" {} ", title), theme::header()),
        ]),
        Line::from(vec![
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
        ]),
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

                lines.push(Line::from(vec![
                    Span::styled(format!(" {} ", cursor_char), cursor_style),
                    Span::styled("[", check_style),
                    Span::styled(check_char, check_style),
                    Span::styled("] ", check_style),
                    Span::styled(format!("{:<24}", name), name_style),
                    Span::styled(description.to_string(), theme::hint()),
                ]));
            }
        }
    }

    let list = Paragraph::new(lines);
    f.render_widget(list, list_area);

    // Footer
    let selected_count = state.selected_count();
    let footer = Paragraph::new(Line::from(vec![
        Span::styled(
            format!("  {} selected", selected_count),
            Style::default().fg(theme::GREEN),
        ),
    ])).block(Block::default().borders(Borders::TOP));
    f.render_widget(footer, chunks[2]);
}

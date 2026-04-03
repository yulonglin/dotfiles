pub mod state;

use crossterm::event::{self, Event, KeyCode, KeyEventKind};
use crossterm::terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen};
use crossterm::ExecutableCommand;
use ratatui::prelude::*;
use ratatui::widgets::{Block, Borders, Paragraph};

use state::{AppState, ListItem};
use crate::ignore::patterns::PatternState;
use crate::context::tui::theme;

pub fn run() -> Result<(), Box<dyn std::error::Error>> {
    let dot_dir = super::find_dotfiles_dir()?;
    let patterns_path = format!("{}/config/ignore/patterns", dot_dir);
    let categories = crate::ignore::patterns::parse_patterns_file(&patterns_path)?;

    let git_root = super::find_git_root()?;
    let gitignore_path = format!("{}/.gitignore", git_root);
    let ignore_path = format!("{}/.ignore", git_root);

    let mut state = AppState::new(&categories, &gitignore_path, &ignore_path);

    enable_raw_mode()?;
    std::io::stdout().execute(EnterAlternateScreen)?;

    let result = run_loop(&mut state);

    let _ = disable_raw_mode();
    let _ = std::io::stdout().execute(LeaveAlternateScreen);

    result?;

    if state.apply {
        let selections = state.selections();
        let gi_warnings = super::managed::apply(&gitignore_path, &selections, false)?;
        let ig_warnings = super::managed::apply(&ignore_path, &selections, true)?;

        for w in gi_warnings.iter().chain(ig_warnings.iter()) {
            eprintln!("  warning: {}", w);
        }
        super::print_summary(&selections);
    }

    Ok(())
}

fn run_loop(state: &mut AppState) -> Result<(), Box<dyn std::error::Error>> {
    let mut terminal = ratatui::init();

    loop {
        terminal.draw(|f| render(f, state))?;

        if let Event::Key(key) = event::read()? {
            if key.kind != KeyEventKind::Press { continue; }
            match key.code {
                KeyCode::Char('q') | KeyCode::Esc => { state.quit = true; break; }
                KeyCode::Enter => { state.apply = true; break; }
                KeyCode::Char(' ') => state.toggle(),
                KeyCode::Down | KeyCode::Char('j') => state.move_down(),
                KeyCode::Up | KeyCode::Char('k') => state.move_up(),
                _ => {}
            }
        }
    }

    ratatui::restore();
    Ok(())
}

fn render(f: &mut ratatui::Frame, state: &AppState) {
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
            Span::styled(" claude-tools ignore ", theme::header()),
        ]),
        Line::from(vec![
            Span::styled(" j/k ", theme::hint()),
            Span::raw("navigate  "),
            Span::styled("space ", theme::hint()),
            Span::raw("cycle  "),
            Span::styled("enter ", theme::hint()),
            Span::raw("apply  "),
            Span::styled("q ", theme::hint()),
            Span::raw("quit"),
        ]),
    ]).block(Block::default().borders(Borders::BOTTOM));
    f.render_widget(header, chunks[0]);

    // List area
    let list_area = chunks[1];
    let mut lines: Vec<Line> = Vec::new();

    // Legend
    lines.push(Line::from(vec![
        Span::styled("  [   ] ", Style::default().fg(theme::GRAY)),
        Span::raw("skip  "),
        Span::styled("[ G ] ", Style::default().fg(theme::YELLOW)),
        Span::raw("gitignore  "),
        Span::styled("[G+S] ", Style::default().fg(theme::GREEN)),
        Span::raw("gitignore + searchable"),
    ]));
    lines.push(Line::raw(""));

    let visible_height = list_area.height.saturating_sub(3) as usize;
    let scroll_offset = if state.cursor > visible_height / 2 {
        state.cursor.saturating_sub(visible_height / 2)
    } else {
        0
    };

    for (i, item) in state.items.iter().enumerate().skip(scroll_offset).take(visible_height) {
        match item {
            ListItem::CategoryHeader { name, description } => {
                lines.push(Line::from(vec![
                    Span::styled(format!("  {} ", name), theme::header()),
                    Span::styled(format!("-- {}", description), theme::hint()),
                ]));
            }
            ListItem::PatternRow { glob, description, state: pat_state, .. } => {
                let is_cursor = i == state.cursor;
                let bracket_style = match pat_state {
                    PatternState::Skip => Style::default().fg(theme::GRAY),
                    PatternState::Gitignore => Style::default().fg(theme::YELLOW),
                    PatternState::GitignoreSearchable => Style::default().fg(theme::GREEN),
                };
                let label = pat_state.label();
                let cursor_char = if is_cursor { ">" } else { " " };
                let cursor_style = if is_cursor { theme::cursor() } else { Style::default() };

                lines.push(Line::from(vec![
                    Span::styled(format!(" {} ", cursor_char), cursor_style),
                    Span::styled("[", bracket_style),
                    Span::styled(label, bracket_style),
                    Span::styled("] ", bracket_style),
                    Span::styled(format!("{:<24}", glob), if is_cursor { theme::cursor() } else { theme::unselected() }),
                    Span::styled(description.to_string(), theme::hint()),
                ]));
            }
        }
    }

    let list = Paragraph::new(lines);
    f.render_widget(list, list_area);

    // Footer
    let footer = Paragraph::new(Line::from(vec![
        Span::styled(format!("  {} patterns -> .gitignore", state.gitignore_count()), Style::default().fg(theme::YELLOW)),
        Span::raw("   "),
        Span::styled(format!("{} patterns -> .ignore", state.ignore_count()), Style::default().fg(theme::GREEN)),
    ])).block(Block::default().borders(Borders::TOP));
    f.render_widget(footer, chunks[2]);
}

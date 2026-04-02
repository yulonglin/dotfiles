use ratatui::style::{Color, Modifier, Style};

pub const TITLE: &str = " claude-context ";

pub const GREEN: Color = Color::Green;
pub const YELLOW: Color = Color::Yellow;
pub const BLUE: Color = Color::Blue;
pub const GRAY: Color = Color::DarkGray;
pub const WHITE: Color = Color::White;

pub fn selected() -> Style {
    Style::default().fg(GREEN).add_modifier(Modifier::BOLD)
}

pub fn unselected() -> Style {
    Style::default().fg(WHITE)
}

pub fn cursor() -> Style {
    Style::default().fg(BLUE).add_modifier(Modifier::BOLD)
}

pub fn header() -> Style {
    Style::default().fg(WHITE).add_modifier(Modifier::BOLD)
}

pub fn hint() -> Style {
    Style::default().fg(GRAY)
}

pub fn modified_indicator() -> Style {
    Style::default().fg(YELLOW)
}

pub fn tree_branch() -> Style {
    Style::default().fg(GRAY)
}

pub const FILLED: &str = "●";
pub const EMPTY: &str = "○";
pub const BRANCH: &str = "├";
pub const BRANCH_LAST: &str = "└";

//! Home timezone configuration for the statusline workday indicator.
//!
//! Stores the user's home timezone in `~/.config/claude-tools/timezone` so that
//! the workday remaining display uses the correct local time even on remote servers.

use std::io::{self, Write};

// --- Timezone options ---

const TIMEZONES: &[(&str, &str, &str)] = &[
    ("UK",     "Europe/London",       "GMT/BST (UTC+0 winter, UTC+1 summer)"),
    ("PT",     "America/Los_Angeles", "PST/PDT (UTC−8 winter, UTC−7 summer)"),
    ("SGT",    "Asia/Singapore",      "SGT (UTC+8, no DST)"),
    ("Brazil", "America/Sao_Paulo",   "BRT/BRST (UTC−3 winter, UTC−2 summer)"),
];

// --- Config path ---

fn config_path() -> Option<std::path::PathBuf> {
    let home = std::env::var("HOME").ok()?;
    let dir = std::path::PathBuf::from(format!("{}/.config/claude-tools", home));
    std::fs::create_dir_all(&dir).ok()?;
    Some(dir.join("timezone"))
}

/// Read the configured home timezone. Returns `None` if unset.
pub fn read_home_timezone() -> Option<String> {
    let path = config_path()?;
    let s = std::fs::read_to_string(path).ok()?;
    let s = s.trim().to_string();
    if s.is_empty() { None } else { Some(s) }
}

fn write_timezone(tz: &str) -> Result<(), Box<dyn std::error::Error>> {
    let path = config_path().ok_or("could not determine config path")?;
    std::fs::write(path, format!("{}\n", tz))?;
    Ok(())
}

// --- Interactive picker ---

pub fn run() -> Result<(), Box<dyn std::error::Error>> {
    let current = read_home_timezone();

    println!("\x1b[1mHome timezone\x1b[0m (used for workday indicator on remote servers)\n");

    for (i, (label, tz, desc)) in TIMEZONES.iter().enumerate() {
        let marker = if current.as_deref() == Some(tz) { " \x1b[32m✓\x1b[0m" } else { "" };
        println!("  \x1b[1m{}\x1b[0m. \x1b[36m{:<8}\x1b[0m  {}  \x1b[2m({})\x1b[0m{}",
            i + 1, label, tz, desc, marker);
    }

    if let Some(ref tz) = current {
        if !TIMEZONES.iter().any(|(_, t, _)| *t == tz) {
            println!("\n  \x1b[2mCurrent (custom): {}\x1b[0m", tz);
        }
    }

    println!("\n  \x1b[2m0. Clear (use server local time)\x1b[0m");
    println!();
    print!("Select [1-{}] or 0 to clear: ", TIMEZONES.len());
    io::stdout().flush()?;

    let mut input = String::new();
    io::stdin().read_line(&mut input)?;
    let choice = input.trim();

    match choice {
        "0" => {
            if let Some(path) = config_path() {
                let _ = std::fs::remove_file(path);
            }
            println!("\x1b[2mTimezone cleared — using server local time.\x1b[0m");
        }
        s => {
            let n: usize = s.parse().unwrap_or(0);
            if n >= 1 && n <= TIMEZONES.len() {
                let (label, tz, _) = TIMEZONES[n - 1];
                write_timezone(tz)?;
                println!("\x1b[32mTimezone set to {} ({})\x1b[0m", tz, label);
            } else {
                eprintln!("Invalid selection.");
                std::process::exit(1);
            }
        }
    }

    Ok(())
}

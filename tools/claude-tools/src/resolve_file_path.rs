/// PostToolUse hook: Guide Claude to search when Read fails with file-not-found.
/// Fast path (~0.5ms) — avoids fork+exec overhead of shell fallback.
use serde::Deserialize;
use std::io::Read;
use std::path::Path;

#[derive(Deserialize)]
struct Input {
    tool_name: Option<String>,
    tool_input: Option<ToolInput>,
    tool_response: Option<serde_json::Value>,
}

#[derive(Deserialize)]
struct ToolInput {
    file_path: Option<String>,
}

pub fn run() -> Result<(), Box<dyn std::error::Error>> {
    let mut input_str = String::new();
    std::io::stdin().read_to_string(&mut input_str)?;
    let input: Input = serde_json::from_str(&input_str)?;

    // Only handle Read tool
    if input.tool_name.as_deref() != Some("Read") {
        return Ok(());
    }

    // Check if response indicates file-not-found
    let response_str = match &input.tool_response {
        Some(v) => v.to_string().to_lowercase(),
        None => return Ok(()),
    };

    let is_not_found = ["does not exist", "no such file", "enoent", "not found"]
        .iter()
        .any(|pattern| response_str.contains(pattern));

    if !is_not_found {
        return Ok(());
    }

    // Extract path info for search guidance
    let file_path = input
        .tool_input
        .as_ref()
        .and_then(|ti| ti.file_path.as_deref())
        .unwrap_or("");

    let path = Path::new(file_path);
    let basename = path.file_name().and_then(|f| f.to_str()).unwrap_or("");

    if basename.is_empty() {
        return Ok(());
    }

    // Preserve directory hint if present
    let parent_name = path
        .parent()
        .and_then(|p| p.file_name())
        .and_then(|f| f.to_str())
        .unwrap_or("");

    let search_hint = if !parent_name.is_empty() && parent_name != "/" {
        format!(
            "Glob(\"**/{}/{}\") first, then Glob(\"**/{}\") if no results",
            parent_name, basename, basename
        )
    } else {
        format!("Glob(\"**/{}\") or fd -H \"{}\"", basename, basename)
    };

    let msg = format!(
        "File not found at {}. REQUIRED: Search before giving up.\n\
         1. {}\n\
         2. Single match → Read it. Multiple → list candidates and ask user.\n\
         3. Zero matches → ask user for correct path or repo.\n\
         Never silently skip a referenced file.",
        file_path, search_hint
    );

    println!("{}", serde_json::json!({ "systemMessage": msg }));
    Ok(())
}

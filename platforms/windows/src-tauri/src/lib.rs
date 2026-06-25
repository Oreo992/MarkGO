// MarkGo Windows shell. Thin Rust host that wires the dialog/fs/opener plugins
// and exposes a couple of helper commands to the WebView2 frontend.

mod ai;

use std::path::Path;

#[derive(serde::Serialize)]
struct OpenedDocument {
    text: String,
    path: String,
    name: String,
}

/// Reads a Markdown file directly (used for "open with" / drag-drop launches).
#[tauri::command]
fn read_markdown(path: String) -> Result<OpenedDocument, String> {
    let text = std::fs::read_to_string(&path).map_err(|e| e.to_string())?;
    let name = Path::new(&path)
        .file_stem()
        .and_then(|s| s.to_str())
        .unwrap_or("Markdown")
        .to_string();
    Ok(OpenedDocument { text, path, name })
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    let mut builder = tauri::Builder::default()
        .manage(ai::AiState::default())
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_fs::init())
        .plugin(tauri_plugin_process::init());

    // Auto-updater is desktop-only and verifies releases against the embedded
    // public key (see plugins.updater in tauri.conf.json).
    #[cfg(desktop)]
    {
        builder = builder.plugin(tauri_plugin_updater::Builder::new().build());
    }

    builder
        .invoke_handler(tauri::generate_handler![
            read_markdown,
            ai::ai_set_config,
            ai::ai_get_status,
            ai::ai_stream,
            ai::ai_cancel
        ])
        .run(tauri::generate_context!())
        .expect("error while running MarkGo");
}

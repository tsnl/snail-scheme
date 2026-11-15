// Zed's extension for `snail-scheme`. The language itself is data:
// extension.toml names the tree-sitter grammar in
// editors/tree-sitter-snail-scheme, and languages/snail-scheme/ holds its
// queries. This code answers the one question Zed asks in code: how to start
// the language server, `snail-scheme lsp`, which is a `snail-scheme` program
// (src/snail/shell/lsp.sld).
//
// Zed's extension host loads a component without WasmGC, so the extension
// cannot be compiled from `snail-scheme`; it stays this small.

use zed_extension_api::{self as zed, settings::LspSettings, LanguageServerId, Result, Worktree};

struct SnailExtension;

// ---- Finding the launcher ----

// The launcher `./snail-scheme` at the repository's root, by what it begins
// with, so a worktree's file of that name that is something else is not run.
fn worktree_launcher(worktree: &Worktree) -> Option<String> {
    let text = worktree.read_text_file("snail-scheme").ok()?;
    text.starts_with("#!/bin/sh")
        .then(|| format!("{}/snail-scheme", worktree.root_path()))
}

// The command the settings name (`lsp.snail-scheme.binary`), then a
// `snail-scheme` on the shell's PATH, then the worktree's own launcher. Settings that name only
// arguments keep the launcher found.
fn command(worktree: &Worktree) -> Result<zed::Command> {
    let binary = LspSettings::for_worktree("snail-scheme", worktree)
        .ok()
        .and_then(|settings| settings.binary);
    let configured = binary.as_ref().and_then(|binary| binary.path.clone());
    let program = configured
        .or_else(|| worktree.which("snail-scheme"))
        .or_else(|| worktree_launcher(worktree))
        .ok_or_else(|| {
            "no `snail-scheme` launcher: open the snail-scheme repository, put its \
             `snail-scheme` on PATH, or set lsp.snail-scheme.binary.path"
                .to_string()
        })?;
    let args = binary
        .and_then(|binary| binary.arguments)
        .unwrap_or_else(|| vec!["lsp".to_string()]);
    Ok(zed::Command {
        command: program,
        args,
        env: worktree.shell_env(),
    })
}

// ---- The extension ----

impl zed::Extension for SnailExtension {
    fn new() -> Self {
        SnailExtension
    }

    fn language_server_command(
        &mut self,
        _language_server_id: &LanguageServerId,
        worktree: &Worktree,
    ) -> Result<zed::Command> {
        command(worktree)
    }
}

zed::register_extension!(SnailExtension);

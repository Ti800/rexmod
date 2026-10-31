# Changelog

All notable changes to rexmod. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [0.1.0] - 2026-11-01

First release.

### Added

- Changes panel on the right of the Rex window: Last Turn, Uncommitted and Branch change sets, and a Files tab, styled like Rex's own sidebar. `⌘⇧E` shows or hides it; the toggle sits with the pane actions.
- Editor pane: click a file and it opens in Neovim next to your agent, at the changed line; one editor per tab.
- Review comments: `<Space>r` on a line or selection in the editor; they reach the agent with your next message, or right away from the panel.
- `⌘P` file picker over the agent's repository, with the editor's syntax highlighting in the preview.
- Works with every agent Rex supports: Claude Code and Codex (hooks), OpenCode (plugin), Pi (extension). With several agents in a tab the panel follows the one you focused last.
- Language support on demand in the editor: open a file and its tree-sitter parser and language server are installed and started.
- Installer for a clean Mac, an uninstaller, and a LaunchAgent that re-applies the patch after Rex updates itself.

# Agent Files

Agent Files is a macOS 26 app for managing the instruction files of Claude Code, Codex, Factory, Cursor, Grok Build, and Warp from one place.

## How it works

Each workspace keeps one shared text and remembers which lines differ in each file:

- **Global** manages each agent's user instructions: `~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md`, `~/.factory/AGENTS.md`, and `~/.grok/AGENTS.md`. Cursor and Warp keep user rules in their own settings, so they get a variant you copy into Cursor Settings > Rules or Warp's rules.
- **Projects** manage a folder's `AGENTS.md` (Codex, Cursor, Factory, Grok Build, Warp) and `CLAUDE.md` (Claude Code).

Setting up a workspace imports the existing files without changing them. Pick one file as the starting point, and the differences in the other files are kept as file-specific lines.

- **Edit** shows the exact contents of one file. Save edits for every file, or only for the file you are editing.
- **Differences** compares every file with the selected tab in a GitHub-style diff: removed and added lines, changed words highlighted, and unchanged lines folded. Use for All makes one version shared.
- Files edited in another app are flagged. Review the change, then keep it for that file, share it with every file, or discard it.

Agents appear with the icons of their installed apps. Grok Build has no desktop app, so it uses a drawn mark.

Files stay plain Markdown. The template is stored in `~/Library/Application Support/Agent Files/Templates/`, and every file is backed up before the app overwrites it.

**Skills** is a secondary library for comparing and syncing skill folders across agents.

## Run

```sh
./script/build_and_run.sh
```

Use `./script/build_and_run.sh --verify` to build, launch, and confirm that the process stays running. Set `AGENT_FILES_HOME=/path/to/folder` and launch the binary in `dist/Agent Files.app/Contents/MacOS/` to try the app against a sandboxed home folder.

## Test

```sh
./script/test.sh
```

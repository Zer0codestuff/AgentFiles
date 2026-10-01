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

## Sync across computers

Open **Sync** in the toolbar and choose **Connect Sync**. Agent Files creates or connects a private `agent-files-sync` repository in the signed-in GitHub account. If sign-in is needed, choose **Sign In to GitHub** and authorize the displayed code once in the browser. Repository setup, synchronization, conflict review, and recovery happen in Agent Files.

Keep the app open on each Mac. It checks for changes every minute, after saving instructions, and when the app becomes active. Offline edits stay local until the next successful sync. You can pause automatic sync or use **Sync Now**.

- Global instruction variants sync across Macs, including variants for agents installed only on another computer. Cursor and Warp still require pasting their text into their app settings.
- Project instructions sync after you set up the workspace. On another Mac, choose **Choose Folder** for each synced project to map it to its local folder. Existing instructions are kept and compared before replacement.
- If both computers edit a workspace, **Compare** shows both versions in the app. Choose **Keep This Computer** or **Use Synced Version**. Sync waits for your choice. Backups and repository history preserve replaced content.
- Files edited outside Agent Files keep their changes and use the existing workspace review flow.
- Removing a project or disconnecting a computer keeps its instruction files and the private archive. **Restore Saved Archive** repairs missing archive records inside the app.

Only instruction templates, agent keys, and workspace names are uploaded. Skills, local folder paths, app configuration, and credentials are excluded. The archive uses `agent-files.json` plus plain Markdown copies under `instructions/`. Each upload publishes all files in one Git commit and never forces the branch over another computer's update. The manifest is the source of truth; Markdown copies are exports managed by the app. The implementation uses GitHub's [Git trees](https://docs.github.com/en/rest/git/trees#create-a-tree) and [reference updates](https://docs.github.com/en/rest/git/refs#update-a-reference).

The built app bundles GitHub CLI for sign-in, so another Mac does not need to install it separately. The build machine needs `gh` available to include this helper. Local sync settings and the last common version live in `instruction-sync.json` beside the app configuration. Tokens are read through GitHub CLI and never written to the sync archive or app settings.

## Run

```sh
./script/build_and_run.sh
```

Use `./script/build_and_run.sh --verify` to build, launch, and confirm that the process stays running. Set `AGENT_FILES_HOME=/path/to/folder` and launch the binary in `dist/Agent Files.app/Contents/MacOS/` to try the app against a sandboxed home folder.

The current local build targets Apple Silicon Macs running macOS 26 or later. Signing is ad hoc; signed distribution and notarization are separate follow-up work.

## Test

```sh
./script/test.sh
```

# Agent Files project guide

## Purpose and architecture

Agent Files is a macOS 26 SwiftUI app for managing the instruction files of Claude Code, Codex, Factory, Cursor, Grok Build, and Warp. Each workspace (Global, or one project) owns one `InstructionTemplate`: shared lines plus lines limited to some files through `only` and `except` audiences. Rendering the template for a file key produces that file's exact contents, so instruction files never contain markers. Templates live in `Application Support/Agent Files/Templates/`.

`AgentFilesStore` owns app state. `LineDiff` powers imports, edits, and the diff views. Editing a file applies its line diff back to the template, either shared with every file that has the changed lines or kept only in that file. Files changed in another app are flagged and never overwritten until the user keeps or discards the change. Skills are a secondary library in `AgentFilesStore+Skills.swift` and `SkillLibraryService`.

Global workspaces include Cursor and Warp as copy-only targets (`WorkspaceTarget.writesFile == false`) because both keep user rules in app settings. `AppIconProvider` loads agent icons from installed apps through Launch Services, with a drawn `GrokMark` for Grok Build.

Instruction sync uses a private GitHub repository as a data store. `AgentFilesStore+InstructionSync.swift` compares local templates, the last common archive, and the current cloud archive. `GitHubInstructionSync` publishes `agent-files.json` and plain Markdown exports in one Git tree and commit, then updates the branch without force. Concurrent changes require review inside `InstructionSyncView`. `instruction-sync.json`, beside the local configuration, stores the common archive and per-computer project bindings. Global has a stable cloud ID; projects use UUIDs and explicit local folder mapping. Skills, local paths, and credentials are excluded. The build bundles GitHub CLI for existing authentication and one-time browser sign-in.

Views use a two-column `NavigationSplitView`: a sidebar with Global, projects, and Skills, and a detail pane with per-file tabs, an Edit mode, and a Differences mode. Differences is a GitHub-style diff: the selected tab is the reference, every other file gets a card with numbered red and green lines, changed words highlighted, and folded unchanged lines. `FileComparison` builds these diffs from the template, so each hunk maps to a `TemplateVariation` for Use for All. The app is a regular Dock app and quits when its window closes.

The app icon is an Icon Composer file at `Icon/AppIcon.icon`, drawn by `script/make_icon.swift` and compiled with `actool` during the build, so macOS 26 applies its own shape and glass.

## Run, build, and test

- Run the app with `./script/build_and_run.sh`.
- Verify launch with `./script/build_and_run.sh --verify`.
- Build with `swift build`.
- Run focused package tests with `./script/test.sh`.
- Regenerate the icon layers with `swift script/make_icon.swift Icon/AppIcon.icon`. The build needs Xcode 26 for `actool`.

The run script stages and ad hoc signs `dist/Agent Files.app`. Codex's Run action is configured in `.codex/environments/environment.toml`.
The test script invokes `swift test` with the active toolchain's Swift Testing framework paths. This is required by the current Command Line Tools installation.

## Current status

The repository targets macOS 26 and Swift 6. On 2026-10-01, 43 focused tests passed, including two-computer synchronization, conflict choices, concurrent uploads, outside edits, folder mapping, newly installed agents, and archive recovery. The private sync repository was created through the app and the first real Global upload was verified without changing managed files. The sync and conflict windows were visually checked, and a conflict was resolved through the app against an isolated home folder. Set `AGENT_FILES_HOME` to run the app against a sandboxed home folder instead of the real one.

## Recent changes

- Added automatic private GitHub sync for instruction workspaces, with in-app conflict review, explicit project folder mapping, offline retry, and archive recovery.
- Preserved Global variants for agents installed only on another computer during local edits. Bundled GitHub CLI and its license for sign-in without a separate install on each Mac.
- Rebuilt Differences as a GitHub-style diff against the selected tab, with `+N −N` counts on the other tabs, word highlights, and Use for All per hunk.
- Added the app icon: three stacked sheets (Grok violet, Codex blue, and a white sheet with a Claude orange heading) on a dark tile.
- Replaced sync groups, layers, and the menu bar extra with template-based workspaces for Global and project instructions.
- Added per-file editing with a shared or file-only save scope, a Differences view with Use for All, and review for files changed outside the app.
- Added Cursor and Warp to Global as copy-only targets and replaced symbol badges with real app icons.
- Kept Skills as a secondary library with comparison, install, sync previews, backups, and opt-in Keep in Sync.

## Project preferences and constraints

- Keep source, UI copy, documentation, and metadata in English.
- Use native SwiftUI structure and system Liquid Glass before custom materials.
- Keep the sidebar lightweight and preserve maximum editor space.
- Back up content before any app-initiated overwrite.
- Treat concurrent changes as a conflict. Never choose a winner silently.
- Treat GitHub as a data store. Keep repository creation, synchronization, conflict decisions, and recovery inside the app; only account authorization uses the browser.
- Automatic instruction writes require the user to connect sync. Preserve the existing protection for files changed outside the app.
- Keep user-selected files outside the app sandbox until security-scoped bookmarks are implemented.

## Known issues and next steps

- Grok Build loads both `AGENTS.md` and `Claude.md` in a project, so a project workspace gives Grok duplicate instructions.
- Workspaces only manage the default files. Adding custom files, such as `GEMINI.md`, is not supported yet.
- Cursor and Warp keep user rules outside the file system. Their Global variants must be pasted into each app's settings by hand.
- Add signed distribution and security-scoped bookmarks if the app is sandboxed.
- Sync runs while the app is open. Conflicts are reviewed for a whole workspace, and removing a project only disconnects it locally. The archive is limited to 8 MB.
- GitHub CLI must be installed on the build machine to bundle sign-in. The current local build is Apple Silicon only and uses ad hoc signing.

## Do not

- Do not delete, rename, or move managed instruction files.
- Do not write instruction files except through an explicit user action or automatic instruction sync that the user explicitly enabled.
- Do not sync skills, local filesystem paths, credentials, or the app configuration to GitHub.
- Do not require GitHub website operations, terminal commands, pull requests, or manual merges to use instruction sync.
- Do not force-push the sync archive or propagate local project removal as a remote deletion.
- Do not allow one path to belong to multiple workspaces.
- Do not overwrite a skill folder without backing it up first.
- Do not overwrite a file after concurrent edits without an explicit user action.
- Do not replace native macOS sidebars, toolbars, or controls with custom chrome.
- Do not add markers or other app metadata to instruction files.
- Do not ship the icon as a plain `.icns` only; macOS 26 puts it in a gray frame.

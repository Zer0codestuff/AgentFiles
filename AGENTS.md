# Agent Files project guide

## Purpose and architecture

Agent Files is a macOS 26 SwiftUI menu bar app that groups and synchronizes text instruction files. `AgentFilesStore` owns app state. Models are Codable value types. Services handle file I/O, backups, directory observation, open panels, persistence, and synchronization planning. Views use a three-column `NavigationSplitView`, a dedicated settings scene, and a `MenuBarExtra`.

Whole-file replacement is the only active synchronization strategy. Keep strategy resolution separate so shared blocks and local protected sections can be added later without changing file observation or persistence.

## Run, build, and test

- Run the app with `./script/build_and_run.sh`.
- Verify launch with `./script/build_and_run.sh --verify`.
- Build with `swift build`.
- Run focused package tests with `./script/test.sh`.

The run script stages and ad hoc signs `dist/Agent Files.app`. Codex's Run action is configured in `.codex/environments/environment.toml`.
The test script invokes `swift test` with the active toolchain's Swift Testing framework paths. This is required by the current Command Line Tools installation.

## Current status

The first functional version is complete. The repository targets macOS 26 and Swift 6. The app is intentionally menu-bar-only and does not show a Dock icon. On 2026-08-30, all eight focused tests passed, the staged app bundle launched successfully, and the main window, group sheet, and settings scenes were checked in the running app.

## Recent changes

- Added SwiftPM app and test targets, the staged `.app` build script, and the Codex Run action.
- Added persistent sync groups, UTF-8 file management, automatic directory observation, editor saves, and app-wide plus per-group sync switches.
- Added whole-file synchronization behind a strategy protocol, concurrent-edit detection, atomic writes, and up to 20 backups per managed file.
- Added the three-column SwiftUI window, Liquid Glass controls, menu bar scene, settings, group and file management, search, and file editor.
- Added focused tests for planning, conflicts, persistence, backup retention, disabled sync, and external-editor propagation.

## Project preferences and constraints

- Keep source, UI copy, documentation, and metadata in English.
- Use native SwiftUI structure and system Liquid Glass before custom materials.
- Keep the sidebar lightweight and preserve maximum editor space.
- Back up content before any app-initiated overwrite.
- Treat concurrent changes as a conflict. Never choose a winner silently.
- Keep user-selected files outside the app sandbox until security-scoped bookmarks are implemented.

## Known issues and next steps

- Add section-aware synchronization with shared and local block markers.
- Add signed distribution and security-scoped bookmarks if the app is sandboxed.
- Add a Launch at Login preference if the app should start automatically after sign-in.

## Do not

- Do not delete, rename, or move managed instruction files.
- Do not synchronize while the global or group automatic-sync switch is off.
- Do not allow one path to belong to multiple sync groups.
- Do not overwrite a file after concurrent edits without an explicit user action.
- Do not replace native macOS sidebars, toolbars, or controls with custom chrome.

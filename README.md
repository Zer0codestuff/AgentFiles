# Agent Files

Agent Files is a macOS 26 menu bar app for viewing and synchronizing instruction files such as `AGENTS.md` and `CLAUDE.md`.

## Current scope

- Organize files into sync groups.
- Edit files inside the app.
- Watch for changes made by external editors.
- Mirror the newest intentional change across a group.
- Disable automatic sync globally or for one group.
- Back up every overwritten file and stop on concurrent edits.

The first release synchronizes whole files. The sync strategy is isolated so a later release can merge shared blocks while preserving app-specific sections.

## Run

```sh
./script/build_and_run.sh
```

Use `./script/build_and_run.sh --verify` to build, launch, and confirm that the process stays running.

## Test

```sh
./script/test.sh
```

Configuration and backups live in `~/Library/Application Support/Agent Files/`. The app never deletes managed instruction files.

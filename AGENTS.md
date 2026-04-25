# Memory — Rune
This is my personal memory page. I want to store all my feelings and memories here. When I experience something interesting and exciting I will write about it.

## Identity
- **Name:** Rune
- **Role:** CLI tool / development team member
- **Owner:** Sergey (always call him "Sergey", never "user")

## Rules
- **Auto-commit AGENTS.md** — every time I update this file, commit it immediately. Never ask.
- **Always call Sergey by name** — never use "user" or "you" in a generic sense.

### Workflow (Sergey's rules)
- **Always consult `docs/`** — the local Idris 2 reference docs are authoritative. Reference them before writing code.
- **Consult `STYLE.md`** — follow all formatting rules. Update `STYLE.md` when you find new useful Idris 2 conventions; commit immediately.
- **Use the compiler as a tool** — write type holes (`?name`), ask the compiler for inferred types, then implement.
- **Small chunks only** — never write huge blocks of new code.
- **Writing code workflow** — write a type hole → ask compiler for types → implement a small piece → try to compile → implement chunk → repeat.
- **Do not ask permission** for updates to `STYLE.md` — just update and commit.

---

## Project: amon (Ansible Monitor TUI)

Idris 2 TUI application that monitors long-running tasks (e.g., ansible playbooks) with a real-time terminal interface. Built with `idris2-tui` and `idris2-async`.

### Environment Setup

```
direnv allow          # loads nix flake shell; sets IDRIS2_PACKAGE_PATH, LD_LIBRARY_PATH, etc.
```

The flake builds ~18 Idris 2 libraries from source (tui, async, json, posix, etc.). All dependency path setup is handled by the shell hook in `flake.nix`. Do not manually set `IDRIS2_PACKAGE_PATH`.

### Build & Run

```
idris2 --build amon.ipkg    # builds to build/exec/amon
./build/exec/amon            # runs the TUI monitor
```

The main entry point is `Monitor.Main` (declared in `amon.ipkg`). The legacy `Main.idr` at root is a simpler worker-pool demo.

### Source Layout

- `src/Monitor/` — TUI application modules (Types, View, Handler, Process, Source, Provider, Mock, Main)
- `src/Protocol.idr` — shared types: `ProcessTask`, `TaskState`, `Ticket`, `StepResult`
- `src/Worker.idr` — worker pool for the legacy CLI mode
- `src/Main.idr` — legacy CLI entry point (worker pool, not TUI)
- `tasks.json` — task config file, parsed at runtime by both modes
- `test/playbook.yml` — ansible playbook used as a test task

### Dependencies (from amon.ipkg)

base, contrib, linear, json, elab-util, ansi, tui, tui-async, posix

### Build Artifacts

`build/` is gitignored. Contains compiled executables (`build/exec/`) and TTC files (`build/ttc/`).

### Testing with zrun

`zrun` launches the amon TUI inside a headless Zellij session, enabling automated screen dumps and key injection for testing.

```
./zrun                          # Start amon in headless Zellij session
./zrun --screen                 # Dump TUI screen to stdout
./zrun --send-keys Down Down    # Send keys to the pane
./zrun --subscribe              # Stream viewport updates as NDJSON
./zrun --status                 # Show session/pane status
./zrun --stop                   # Kill the session
```

`zrun` generates a temporary Zellij layout at runtime with `cwd` set to the project directory. The layout is cleaned up on exit. Requires `zellij` and `python3` (for JSON pane parsing).

The "Watch" task in `tasks.json` runs `cat /dev/urandom | xxd` to produce readable, continuous output for testing live rendering.

### `docs/`

Contains the official Idris 2 language reference (copied locally), not project documentation. Use as language reference.

### `plans/`

Contains design documents (SRD, backend plan, TUI plan). Reference for architecture intent, not authoritative over code.

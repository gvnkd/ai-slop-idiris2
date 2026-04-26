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
- **Consult `STYLE.md`** — follow all formatting rules. Update `STYLE.md` when you find new useful Idris2 conventions; commit immediately.
- **Use the compiler as a tool** — write type holes (`?name`), ask the compiler for inferred types, then implement.
- **Small chunks only** — never write huge blocks of new code.
- **Writing code workflow** — write a type hole → ask compiler for types → implement a small piece → try to compile → implement chunk → repeat.
- **Do not ask permission** for updates to `STYLE.md` — just update and commit.

### Idris2 Lessons Learned

**`primIO` in `IO` context:** When calling `primIO` inside a function that returns `IO ()`, the compiler may fail to resolve `HasIO IO`. Workaround: wrap with `ignore $ primIO ...` or use `do { ignore $ primIO ...; pure () }`. This happens when the function body is a bare `primIO` expression rather than a `do` block — the type checker struggles to unify the implicit `HasIO` constraint.

**`weakenErrors` inside `try [handler]`:** Adding `weakenErrors` calls inside a `try [onErrno]` block changes the error type from `[Errno]` to a broader type, causing unification failures. Keep `weakenErrors` calls outside `try` blocks, or restructure so logging happens after the `try` completes.

**C FFI shared libraries:** The Idris2-generated wrapper script sets `LD_LIBRARY_PATH` to `$DIR/amon_app`. Custom `.so` files (like `cstr_write.so`) must be copied to `build/exec/amon_app/` at build time. Use `%foreign "C:sym,libname"` syntax where `libname` is the `.so` filename without the `lib` prefix and `.so` extension.

**`spawnCmd` command construction:** The command built with `unwords task.args` is passed to `sh -c`. When the task path is `sh -c "inner command"`, the inner `sh -c` receives only the first word as its command argument. Quote arguments properly or avoid nested `sh -c` patterns.

---

## Project: amon (Ansible Monitor TUI)

Idris 2 TUI application that monitors long-running tasks (e.g., ansible playbooks) with a real-time terminal interface. Built with `idris2-tui` and `idris2-async`. Uses a worker pool (default: 3 parallel jobs); remaining tasks queue and start as slots free up.

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

### Worker Pool

The TUI limits parallel task execution to a configurable number of workers (default: 3 in `Monitor.Main.run`). Tasks beyond the initial batch start in `QUEUED` status (`[Q]`), and are spawned as slots free up when running tasks complete.

**Implementation:**
- `Monitor.Main.run` splits `tasks.json` into initial batch (first N) and queued tasks
- `Monitor.Source.resultsSource` takes `(List ProcInfo, List ProcessTask)` — active processes and queued tasks
- When a process finishes, `resultsSource` spawns the next queued task using `liftIO . spawnCmd`
- Queued jobs appear in the UI as `[Q]`, running as `[R]`, completed as `[+]`/`[x]`

To change the worker count, modify `maxWorkers` in `Monitor.Main.run`.

### Source Layout

- `src/Monitor/` — TUI application modules (Types, View, Handler, Process, Source, Provider, Mock, Main)
- `src/Protocol.idr` — shared types: `ProcessTask`, `TaskState`, `Ticket`, `StepResult`
- `src/Worker.idr` — worker pool for the legacy CLI mode
- `src/Main.idr` — legacy CLI entry point (worker pool, not TUI)
- `src/cstr_write.c` — C FFI helper: `cstr_write()` (write string to fd) and `cstr_timestamp()` (formatted timestamp via strftime). Compiled to `cstr_write.so`, copied to `build/exec/amon_app/` at build time.
- `tasks.json` — task config file, parsed at runtime by both modes
- `test/playbook.yml` — ansible playbook used as a test task

### Logging Subsystem

When a task in `tasks.json` has a `logFile` field defined, all task output is streamed to that file.

**Format:**
- Log begins with `[START] YYYY-MM-DD HH:MM:SS`
- Raw output is written through `tee` (ANSI escape sequences preserved as-is)
- Log ends with `[END] YYYY-MM-DD HH:MM:SS STATUS` (SUCCESS or FAILED)

**Implementation:**
- `spawnCmd` in `Monitor.Process` wraps the command through `tee -a logfile` when `logFile` is set
- On process completion, `pollOne` in `Monitor.Source` calls `writeLogFooter` to append the `[END]` line
- `writeLogFooter` opens the file in append mode (`O_WRONLY | O_APPEND`), writes the footer, and closes

### Dependencies (from amon.ipkg)

base, contrib, linear, json, elab-util, ansi, tui, tui-async, posix

### Build Artifacts

`build/` is gitignored. Contains compiled executables (`build/exec/`) and TTC files (`build/ttc/`).

### C FFI Helpers

Custom C code lives in `src/cstr_write.c` and is compiled to `cstr_write.so` with `gcc -shared -fPIC`. The `.so` must be placed in `build/exec/amon_app/` for the runtime loader to find it. The `.so` is gitignored via `*.so` in `.gitignore`.

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

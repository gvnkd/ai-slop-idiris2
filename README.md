# amon — Ansible Monitor TUI

Idris 2 TUI application that monitors long-running tasks (e.g., ansible playbooks) with a real-time terminal interface. Built with `idris2-tui` and `idris2-async`.

## Features

- **Real-time task output** — live streaming of stdout/stderr from each task
- **Concurrent execution** — configurable worker pool (default: 2 parallel jobs); excess tasks queue and start as slots free up
- **Emoji status badges** — ⏳ Queued, ⏵ Running, ✔ Success, ✘ Failed, ⏱ Timed Out, ⛔ Cancelled
- **Task cancellation** — select a running job and press `x` to send SIGTERM
- **Colored output** — ANSI color codes from tasks pass through to the TUI
- **Task logging** — optional per-task log files with timestamps and status footers
- **Per-task environment variables** — pass `envVars` in `tasks.json` to set environment for individual tasks
- **Timeout support** — tasks auto-terminate after a configurable timeout (uses GNU `timeout`)

## Build and Run

Requires [nix](https://nixos.org/) with flakes enabled:

```sh
direnv allow
idris2 --build amon.ipkg
./build/exec/amon          # default 2 workers
./build/exec/amon 4        # 4 parallel workers
```

## Task Configuration

Tasks are defined in `tasks.json`:

```json
[
  {
    "name": "Ansible",
    "path": "ansible-playbook",
    "args": ["playbook.yml"],
    "timeout": 20,
    "logFile": "logs/ansible.log",
    "blockingIO": true,
    "envVars": {"ANSIBLE_FORCE_COLOR": "True"}
  },
  {
    "name": "Quick Task",
    "path": "ls",
    "args": ["--color=always", "-la"],
    "timeout": 5
  }
]
```

Fields:
- `name` — display label in the TUI
- `path` — command to execute
- `args` — arguments passed to the command
- `timeout` — max seconds before kill (0 = no timeout)
- `logFile` — optional path to write full output log
- `blockingIO` — use blocking I/O mode (for tasks that buffer stdout)
- `envVars` — optional object of environment variables to set for this task

## Task Logging

When `logFile` is set, all task output is streamed to that file:

- Log begins with `[START] YYYY-MM-DD HH:MM:SS`
- Raw output is written through `tee` (ANSI escape sequences preserved)
- Log ends with `[END] YYYY-MM-DD HH:MM:SS STATUS` (SUCCESS, FAILED, or CANCELLED)

## Testing with zrun

`zrun` launches the amon TUI inside a headless [Zellij](https://zellij.dev/) session for automated testing:

```sh
./zrun                        # Start amon in headless session
./zrun --screen               # Dump TUI screen to stdout
./zrun --send-keys Down Down  # Send keys to the pane
./zrun --subscribe            # Stream viewport updates as NDJSON
./zrun --stop                 # Kill the session
```

## Source Layout

```
src/Monitor/
  Main.idr            # TUI entry point, worker pool config
  Types.idr           # JobDisplayStatus, JobUpdate, JobMonitorState
  View.idr            # TUI rendering, emoji badges, colorized output
  Handler.idr         # Key handling (x = cancel), job state updates
  Process.idr         # Process spawning helpers, ANSI utilities
  ProcessStream.idr   # Async process I/O with pipe2(O_CLOEXEC)
  Source.idr          # Event source (JobStarted, JobFinished, etc.)
  Mock.idr            # Mock data for testing
src/Protocol.idr      # Shared types: ProcessTask, TaskState, Ticket
src/Worker.idr        # Worker pool for legacy CLI mode
src/cstr_write.c      # C FFI: cstr_write(), cstr_timestamp()
```

## C FFI Helpers

```sh
gcc -shared -fPIC -o cstr_write.so src/cstr_write.c
cp cstr_write.so build/exec/amon_app/
```

## Playground Examples

```sh
idris2 pg/Main.idr -o pg
./build/exec/pg
```

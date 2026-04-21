# TUI Job Monitor — Backend Sprint Implementation Plan

**Sprint**: Backend Sprint (Real Worker Integration)
**Based On**: `plans/tui_srd.md` §6.3 (Deferred Requirements), `plans/tui_plan.md` §9 (Future Sprint Integration Points)
**Libraries**: idris2-tui (Async mainloop), idris2-async, idris2-async-epoll
**Prerequisite**: Interface sprint completed (current `src/Monitor/` modules)

---

## 1. Goal

Replace mock data providers with real backend integration: load job definitions from `tasks.json`, spawn worker processes, capture stdout/stderr, and display real-time status updates in the TUI.

The TUI transitions from `TUI.MainLoop.Base` (keyboard-only) to `TUI.MainLoop.Async` (keyboard + custom event sources), enabling the UI to update when worker results arrive — not just when keys are pressed.

---

## 2. Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                        Async TUI Mainloop                            │
│                                                                      │
│  ┌──────────────┐                                                   │
│  │ keyboard     │── posts Key events ──────────┐                    │
│  │ (auto)       │                              │                    │
│  └──────────────┘                              │                    │
│  ┌──────────────┐                              ▼                    │
│  │ resultsPoll  │── posts JobUpdate events ──► handler ──► render   │
│  │ EventSource  │                              ▲                    │
│  └──────┬───────┘                              │                    │
│         │ liftIO $ readIORef resultsBuf        │                    │
│         ▼                                      │                    │
│  ┌──────────────┐                              │                    │
│  │ Bridge Thread│  System.Concurrency.fork     │                    │
│  │ reads Chan   │  (blocking, own OS thread)   │                    │
│  │ Result,      │                              │                    │
│  │ writes IORef │                              │                    │
│  └──────┬───────┘                              │                    │
│         │ channelGet (blocking)                │                    │
│         ▼                                      │                    │
│  ┌──────────────┐    ┌───────────┐             │                    │
│  │  Worker 0    │    │  Worker 1 │   ...       │                    │
│  │  (fork)      │    │  (fork)   │             │                    │
│  └──────┬───────┘    └─────┬─────┘             │                    │
│         │ channelPut         │ channelPut       │                    │
│         ▼                    ▼                  │                    │
│  ┌──────────────────────────────────────┐       │                    │
│  │     Channel Result (concurrent)      │       │                    │
│  └──────────────────────────────────────┘       │                    │
│         ▲                    ▲                  │                    │
│  ┌──────┴───────┐    ┌──────┴──────┐           │                    │
│  │  Channel Task│    │ tasks.json  │           │                    │
│  └──────────────┘    └─────────────┘           │                    │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### 2.1 Threading Model

| Component | Threading | Rationale |
|-----------|-----------|-----------|
| Worker pool | `System.Concurrency.fork` (N OS threads) | Blocking IO (`popen`, `pclose`), unchanged from `Worker.idr` |
| Bridge thread | `System.Concurrency.fork` (1 OS thread) | Reads from `Channel Result` (blocking), writes to `IORef` |
| Keyboard EventSource | Async fiber | Non-blocking stdin read via epoll |
| Results EventSource | Async fiber | Non-blocking `IORef` read + async `sleep` for polling |
| Main render loop | Async fiber (epoll) | Processes events from async channel |

### 2.2 Why IORef Bridge?

`System.Concurrency.Channel.channelGet` is a blocking call. The async mainloop's fibers run on the epoll thread. Blocking in an async fiber would stall the entire runtime (keyboard input, rendering, all event sources). The IORef bridge decouples the blocking channel read (in its own OS thread) from the non-blocking async world:

1. Bridge thread: `channelGet resultChan` → append to `IORef (List Worker.Result)`
2. Async EventSource: `liftIO $ readIORef buf` → post `JobUpdate` events → `sleep 100ms` → repeat

`liftIO $ readIORef` is a brief, non-blocking operation — safe for the async runtime.

---

## 3. What Changes vs What Stays

### 3.1 Unchanged Modules

| Module | Notes |
|--------|-------|
| `Protocol.idr` | Domain types unchanged |
| `Worker.idr` | Worker pool logic unchanged |
| `Main.idr` | Kept as standalone non-TUI entry point (not imported by TUI) |
| `Monitor/View.idr` | View instances unchanged — rendering is data-source agnostic |

### 3.2 Modified Modules

| Module | Changes |
|--------|---------|
| `Monitor/Types.idr` | Add `JobUpdate` event type; change `JobMonitorState` to store per-job logs |
| `Monitor/Handler.idr` | Expand handler to process `JobUpdate` events via `Event.union`; change from `Key` to `HSum [JobUpdate, Key]` |
| `Monitor/Main.idr` | Switch from `Base` to `Async` mainloop; add worker pool setup, config loading, bridge thread |
| `amon.ipkg` | Add `tui-async` dependency and new modules |

### 3.3 New Modules

| Module | Purpose |
|--------|---------|
| `Monitor/Provider.idr` | Config loading (`loadTasks`), real log parsing, job-to-entry mapping |
| `Monitor/Source.idr` | Async EventSource for polling worker results from IORef bridge |

### 3.4 Removed / Deprecated Modules

| Module | Notes |
|--------|-------|
| `Monitor/Mock.idr` | Kept in build but no longer imported by `Monitor.Main`. Can be removed later. |

---

## 4. Module-by-Module Specification

### 4.1 `Monitor/Types.idr` — Updated Types

**Additions**:

```idris
import public Worker

public export
data JobUpdate = JobFinished String Worker.Result
```

**State change** — per-job log storage replaces single `logLines`:

```idris
public export
record JobMonitorState where
  constructor MkJobMonitorState
  jobs      : List JobEntry
  selected  : Nat
  jobLogs   : List (List LogLine)   -- logs per job, indexed same as jobs
  logOffset : Nat
```

**Removed**: `logLines` field (replaced by `jobLogs`). The logs for the selected job are now derived: `getSelectedLogs : JobMonitorState -> List LogLine`.

**New helpers**:

```idris
public export
getSelectedLogs : JobMonitorState -> List LogLine
getSelectedLogs st = fromMaybe [] $ indexNat st.selected st.jobLogs

public export
initialState : List JobEntry -> JobMonitorState
initialState jobs = MkJobMonitorState jobs 0 (replicate (length jobs) []) 0
```

**`updateJobByName`**: Find a job by name, update its status and logs:

```idris
public export
updateJobByName : String -> JobDisplayStatus -> List LogLine -> JobMonitorState -> JobMonitorState
```

Updates both the `jobs` list (status) and `jobLogs` list (logs) at the matching index.

### 4.2 `Monitor/Provider.idr` — Config & Real Data

**Imports**: `Protocol`, `Worker`, `Monitor.Types`, `System.File`, `Language.JSON`, `JSON`, `Data.String`

**Functions**:

```idris
public export
loadTasks : String -> IO (Maybe (List ProcessTask))
```
- Moved from `Main.idr` (verbatim or extracted)
- Reads and parses `tasks.json`

```idris
public export
toJobEntries : List ProcessTask -> List JobEntry
```
- Maps `ProcessTask` → `JobEntry` with `QUEUED` status
- Used at startup before dispatching to workers

```idris
public export
parseOutput : Worker.Result -> (JobDisplayStatus, List LogLine)
```
- `Success _ output` → `(SUCCESS, map (MkLogLine "stdout>") (lines output))`
- `Failure _ err` → `(FAILED, map (MkLogLine "stderr>") (lines err))`

```idris
public export
readLogFile : Maybe String -> IO (List LogLine)
```
- Reads from `ProcessTask.logFile` path if present
- Splits into `LogLine` values
- Returns `[]` on missing file or `Nothing` path
- Used for viewing logs of completed jobs (supplementary to `parseOutput`)

```idris
public export
dispatchJobs : List ProcessTask -> Channel Task -> IO ()
```
- Wraps each `ProcessTask` in `MkTicket` with retry count 2
- Sends `Job (MkTicket task {n=2})` for each task
- Sends `Die` for each worker after all tasks (optional: can be deferred)

### 4.3 `Monitor/Source.idr` — Async EventSource

**Imports**: `TUI.MainLoop.Async`, `IO.Async`, `IO.Async.Loop.Posix`, `IO.Async.Loop.Epoll`, `Monitor.Types`, `Worker`, `Data.IORef`, `System.Concurrency`

**Types**:

```idris
public export
0 ResultsBuffer : Type
ResultsBuffer = IORef (List Worker.Result)
```

**Bridge thread** (runs in its own OS thread, blocking):

```idris
public export
bridgeThread : Channel Worker.Result -> ResultsBuffer -> IO ()
bridgeThread resultChan buf = do
  result <- channelGet resultChan
  modifyIORef buf (\rs => rs ++ [result])
  bridgeThread resultChan buf
```

**Async EventSource** (runs as async fiber, non-blocking):

```idris
public export
resultsSource : Has JobUpdate evts => ResultsBuffer -> EventSource evts
resultsSource buf queue = loop 0
  where
    loop : Nat -> NoExcept ()
    loop seen = do
      sleep 100.ms
      current <- liftIO $ readIORef buf
      let newResults = drop seen current
      traverse_ (\r => putEvent queue $ JobFinished r.name r) newResults
      loop (seen + length newResults)
```

- Polls the IORef every 100ms
- Posts `JobUpdate` events for each new result
- Tracks `seen` count to avoid re-processing old results

**Note on `liftIO`**: `liftIO` here refers to the `Async` monad's ability to lift plain `IO` operations. Since `readIORef` is instantaneous, this is safe. If the Idris2 async runtime provides `liftIO` via an instance like `Lift1 World (Async Poll es)`, use that. Otherwise, wrap via `primAsync` or `fromIO` from the async library.

**Note on `sleep`**: `sleep : Has Poller es => Duration -> Async e es ()` — requires `Poller` in the error list. Since our EventSource runs in `NoExcept` (empty error list) inside the epoll app, the `Poller` constraint should be satisfied by the epoll runtime. If type errors arise, adjust the EventSource type or use the `handling` wrapper from `TUI.MainLoop.Async`.

### 4.4 `Monitor/View.idr` — Minimal Updates

The only change is that `View JobMonitorState.paint` now reads logs from `getSelectedLogs` instead of `st.logLines`:

```idris
-- Current:
case st.logLines of
  [] => showTextAt right.nw "No log output"
  _  => paintLogLines right (drop st.logOffset st.logLines)

-- Updated:
let logs = getSelectedLogs st
case logs of
  [] => showTextAt right.nw "No log output"
  _  => paintLogLines right (drop st.logOffset logs)
```

All other View instances remain unchanged.

### 4.5 `Monitor/Handler.idr` — Expanded Handler

**Migration from `Key` to `HSum [JobUpdate, Key]`**:

The handler splits into two separate handlers composed with `Event.union`:

```idris
import TUI.Event
import TUI.Key
import Data.List.Quantifiers
import Data.List.Quantifiers.Extra
import Monitor.Types
import Monitor.Provider

public export
onJobUpdate : Event.Handler JobMonitorState () JobUpdate
onJobUpdate (JobFinished name result) st =
  let (status, logs) = parseOutput result
  in update $ updateJobByName name status logs st

public export
covering
onKey : Event.Handler JobMonitorState () Key
onKey Up st = ...
onKey Down st = ...
-- (same logic as current handler, but using getSelectedLogs for log display)
```

**Key handler changes**:

When the selected job changes (Up/Down), the handler no longer calls `loadMockLogs`. Instead, logs are already stored in `jobLogs`:

```idris
onKey Up st =
  let newSel = case st.selected of 0 => 0; S n => n
  in update $ { selected := newSel, logOffset := 0 } st

onKey Down st =
  let maxIdx = case length st.jobs of 0 => 0; S n => n
      newSel = min maxIdx (st.selected + 1)
  in update $ { selected := newSel, logOffset := 0 } st
```

No IO needed for log loading — logs are maintained in state by `onJobUpdate`.

**Combined handler**:

```idris
public export
handler : Event.Handler JobMonitorState () (HSum [JobUpdate, Key])
handler = union [onJobUpdate, onKey]
```

### 4.6 `Monitor/Main.idr` — Async Entry Point

**Imports**: `TUI.View`, `TUI.MainLoop`, `TUI.MainLoop.Async`, `TUI.Event`, `TUI.Key`, `IO.Async`, `IO.Async.Loop.Posix`, `IO.Async.Loop.Epoll`, `IO.Async.Signal`, `Data.IORef`, `System.Concurrency`, `Monitor.Types`, `Monitor.Provider`, `Monitor.Source`, `Monitor.View`, `Monitor.Handler`

**Startup sequence**:

```idris
covering
run : IO ()
run = do
  -- 1. Setup
  ignore $ system "mkdir -p logs"

  -- 2. Load config
  Just tasks <- loadTasks "tasks.json"
    | Nothing => die "Failed to load tasks.json"

  -- 3. Create channels
  taskChan <- the (IO (Channel Task)) makeChannel
  resultChan <- the (IO (Channel Result)) makeChannel

  -- 4. Spawn workers (unchanged pattern from Main.idr)
  spawnPool 2 taskChan resultChan

  -- 5. Dispatch jobs
  let entries = toJobEntries tasks
  fork $ do
    traverse_ (\t => channelPut taskChan (Job (MkTicket t {n=2}))) tasks
  -- Die messages deferred — workers will block on empty channel, which is fine

  -- 6. Mark all jobs as RUNNING (dispatched to workers)
  let initState = initialState (map (\e => { status := RUNNING } e) entries)

  -- 7. Create results buffer and bridge thread
  resultsBuf <- newIORef []
  fork $ bridgeThread resultChan resultsBuf

  -- 8. Enter async TUI mainloop
  let mainLoop = asyncMain {evts = [JobUpdate, Key]} [resultsSource resultsBuf]
  ignore $ runView mainLoop handler initState

covering
main : IO ()
main = run
```

**spawnPool** — extracted from `Main.idr`:

```idris
spawnPool : Int -> Channel Task -> Channel Result -> IO ()
spawnPool count tasks results =
  ignore $ fork $ traverse_ (\i => fork (worker i tasks results)) [1..count]
```

This can be defined in `Monitor.Main` or extracted to `Monitor.Provider`.

---

## 5. Dependency & Build Setup

### 5.1 Update `amon.ipkg`

```
depends = base >= 0.5.1
       , contrib
       , linear
       , json
       , elab-util
       , ansi
       , tui
       , tui-async

modules = Protocol
       , Worker
       , Monitor.Types
       , Monitor.Mock         -- kept for reference / testing
       , Monitor.Provider     -- new
       , Monitor.Source       -- new
       , Monitor.View
       , Monitor.Handler
       , Monitor.Main
       , Main                 -- kept as non-TUI entry point
```

### 5.2 Already Available in `flake.nix`

All required dependencies are already in `buildInputs` of the dev shell:
- `tui-async` (and its transitive deps: `posix`, `async`, `async-epoll`, `async-posix`, `linux`, `cptr`, `containers`, `elin`, `finite`, `hashable`)

---

## 6. Implementation Order (Tasks)

### Task 1: Update `Monitor.Types` — Add `JobUpdate`, change state

- Add `import public Worker`
- Define `data JobUpdate = JobFinished String Worker.Result`
- Change `JobMonitorState`: replace `logLines` with `jobLogs : List (List LogLine)`
- Add `getSelectedLogs`, `updateJobByName`, update `initialState`
- **Verify build**

### Task 2: Create `Monitor.Provider` — Config loading & data mapping

- Create `src/Monitor/Provider.idr`
- Implement `loadTasks` (copy from `Main.idr`)
- Implement `toJobEntries`, `parseOutput`, `readLogFile`
- Implement `dispatchJobs`
- **Verify build**

### Task 3: Create `Monitor.Source` — EventSource + bridge

- Create `src/Monitor/Source.idr`
- Define `ResultsBuffer` type alias
- Implement `bridgeThread` (plain IO, blocking)
- Implement `resultsSource` (async EventSource, non-blocking)
- **Verify build** — this is the highest-risk step due to async API constraints

### Task 4: Update `Monitor.View` — Use `getSelectedLogs`

- Change `paint` in `View JobMonitorState` to use `getSelectedLogs st` instead of `st.logLines`
- **Verify build**

### Task 5: Rewrite `Monitor.Handler` — Union handler

- Split into `onJobUpdate` and `onKey`
- `onKey`: remove `loadMockLogs` calls; log display comes from state
- `onJobUpdate`: use `parseOutput` + `updateJobByName`
- Combine with `union [onJobUpdate, onKey]`
- Change handler type to `Event.Handler JobMonitorState () (HSum [JobUpdate, Key])`
- **Verify build**

### Task 6: Rewrite `Monitor.Main` — Async mainloop

- Switch from `TUI.MainLoop.Base` to `TUI.MainLoop.Async`
- Implement startup sequence (config → channels → workers → dispatch → buffer → mainloop)
- Extract or inline `spawnPool`
- **Verify build**

### Task 7: Update `amon.ipkg` — Final configuration

- Add `tui-async` to `depends`
- Add `Monitor.Provider`, `Monitor.Source` to `modules`
- **Verify build**

### Task 8: Integration test

- Run `./build/exec/amon` with `tasks.json`
- Verify: jobs start as RUNNING, transition to SUCCESS/FAILED as workers finish
- Verify: selecting a job shows its output in the log viewer
- Verify: j/k scrolls logs, q/Esc exits cleanly
- Verify: all workers complete and results are displayed

### Task 9: Polish

- Handle empty `tasks.json` gracefully (show error or empty list)
- Handle `tasks.json` not found (show error in TUI or exit with message)
- Ensure Die messages are sent to workers on clean exit
- Consider sending `Die` to workers when TUI exits
- **Verify build**

---

## 7. Key Technical Decisions

### 7.1 IORef Bridge vs Direct Async Channel

**Decision**: Use IORef bridge with `System.Concurrency.fork` for the bridge thread.

**Rationale**:
- `System.Concurrency.Channel.channelGet` blocks the calling thread
- The async runtime's fibers run on the epoll thread; blocking stalls everything
- The IORef bridge isolates blocking IO in a separate OS thread
- The async EventSource does only brief, non-blocking `readIORef` calls
- Polling interval (100ms) provides responsive updates without excessive CPU usage

**Alternative considered**: Rewrite workers as async fibers using `IO.Async.Channel`. Rejected because:
- Workers use blocking IO (`popen`, `fGetLine`, `pclose`)
- Would require wrapping all blocking IO in thread-offloading primitives
- More invasive changes to battle-tested `Worker.idr`
- Can be done as a future optimization if needed

### 7.2 Status Tracking: RUNNING at Dispatch

**Decision**: Mark all jobs as RUNNING immediately upon dispatch to the worker pool.

**Rationale**:
- We don't have a "worker started" event from the current `Worker.idr`
- `Worker.Result` only arrives when a job finishes (success or failure)
- Showing QUEUED after dispatch would be misleading — the job is running
- If a "started" notification is desired in the future, add a `JobStarted String` variant to `Worker.Result` or use a separate channel

### 7.3 Per-Job Log Storage in State

**Decision**: Store logs for all jobs in `jobLogs : List (List LogLine)`, indexed by position.

**Rationale**:
- Workers complete asynchronously; logs arrive at any time
- Must store logs even when user isn't viewing that job
- List indexed by position is simple and matches the `jobs` list
- `updateJobByName` finds the job by name and updates at the matching index
- When user selects a job, logs are immediately available (no IO needed)

**Alternative considered**: `SortedMap String (List LogLine)`. More robust but adds dependency on `containers` and complicates state management. List approach is sufficient for < 100 jobs.

### 7.4 Handler Architecture: union

**Decision**: Use `Event.union [onJobUpdate, onKey]` to compose handlers.

**Rationale**:
- Follows the established pattern from `examples/user_event` in idris2-tui
- `union` dispatches `HSum [JobUpdate, Key]` events to the correct sub-handler
- Each sub-handler is a simple `eventT -> stateT -> Result stateT valueT`
- No `HSum` pattern matching needed in business logic

### 7.5 Mock Module Kept

**Decision**: Keep `Monitor.Mock` in the build but don't import it from `Monitor.Main`.

**Rationale**:
- Useful for testing and development (can swap `Provider` for `Mock` during UI work)
- Doesn't affect production behavior since it's not imported
- Can be removed in a cleanup sprint

---

## 8. Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| `liftIO` semantics in async runtime | If `liftIO` blocks the epoll thread, all UI freezes | `readIORef` is instantaneous; if issues arise, use `primAsync` with explicit callback |
| `sleep` availability in `NoExcept` context | Type errors if `Poller` constraint not satisfied | Adjust EventSource type or use `handling` wrapper; consult `TUI.MainLoop.Async` for constraint requirements |
| IORef thread safety | Race between bridge thread (writer) and async fiber (reader) | `IORef` in Idris2 uses atomic CAS; append-only pattern (`rs ++ [result]`) via `modifyIORef` is safe. If contention issues arise, switch to `MVar` or bounded queue |
| 100ms polling latency | UI updates delayed by up to 100ms | Acceptable for job monitoring (NFR-001: 100ms). Reduce to 50ms if needed |
| Worker `Die` on exit | Workers block on empty channel after all jobs complete | Acceptable for this sprint. Future: send Die from TUI exit handler |
| `asyncMain` / `Has Key` constraint resolution | Idris may struggle to resolve `Has Key [JobUpdate, Key]` | Explicit type annotation: `asyncMain {evts = [JobUpdate, Key]}` |
| `tui-async` package not found | Build fails if `tui-async` not in `IDRIS2_PACKAGE_PATH` | Already configured in `flake.nix` dev shell |

---

## 9. File Dependency Graph (Backend Sprint)

```
Protocol.idr ──────────────────────────────────┐
                                               │
Worker.idr ────────────────────────────────┐   │
                                           │   │
Monitor.Types.idr ◄───────────────────────┼───┘
        │                                 │
        ├──► Monitor.Provider.idr ◄───────┘
        │         │
        │         ├──► Monitor.Source.idr ◄── IO.Async.*, System.Concurrency
        │         │
        │         └──► Monitor.Handler.idr ◄── TUI.Event, TUI.Key, HSum/union
        │                   │
        │                   └──► Monitor.Main.idr ◄── TUI.MainLoop.Async
        │                                 │
        └──► Monitor.View.idr ◄── TUI.*   │
                                        ┌──┘
                                        │
                                  amon.ipkg (+ tui-async)
```

---

## 10. Acceptance Criteria

### 10.1 Functional

| # | Criterion | Validation |
|---|-----------|------------|
| BAC-1 | Application loads tasks from `tasks.json` at startup | Delete tasks.json → app exits with error; restore → jobs appear |
| BAC-2 | All jobs start as RUNNING after dispatch | Observe blue `[R]` badges on startup |
| BAC-3 | Jobs transition to SUCCESS/FAILED as workers finish | Watch badges change from blue to green/red |
| BAC-4 | Log viewer shows real command output | Select a completed job → right column shows actual stdout/stderr |
| BAC-5 | UI updates automatically when results arrive (no key press needed) | Wait without pressing keys → observe status changes |
| BAC-6 | Arrow keys navigate job list | Up/Down moves selection |
| BAC-7 | j/k scrolls log viewer | j scrolls down, k scrolls up |
| BAC-8 | q/Esc exits cleanly | App exits, terminal restored |

### 10.2 Contract Validation

| # | Criterion | Validation |
|---|-----------|------------|
| BIC-1 | `Worker.idr` unchanged | `git diff src/Worker.idr` shows no changes |
| BIC-2 | `Protocol.idr` unchanged | `git diff src/Protocol.idr` shows no changes |
| BIC-3 | `Monitor.View.idr` changes are minimal (only log source) | Code review |
| BIC-4 | Handler uses `Event.union` pattern | Type-checking |
| BIC-5 | EventSource is non-blocking (uses `sleep` + `readIORef`) | Code review |
| BIC-6 | `Main.idr` still compiles as standalone non-TUI entry | `idris2 --build mon.ipkg` succeeds |

---

## 11. Future Enhancements (Post-Backend Sprint)

| Enhancement | Description |
|-------------|-------------|
| Worker started notification | Add `JobStarted String` to `Worker.Result` for real RUNNING status |
| Per-job log streaming | Stream stdout lines as they arrive (not just on completion) |
| Graceful shutdown | Send `Die` to workers on TUI exit |
| SIGWINCH handling | Async mainloop already handles SIGWINCH for dynamic resize |
| Log file persistence | Read from `ProcessTask.logFile` on disk for completed jobs |
| Job re-run | Allow user to re-dispatch a completed job |
| Config hot-reload | Watch `tasks.json` for changes and reload |
| Worker pool sizing | Make pool size configurable via CLI flag |

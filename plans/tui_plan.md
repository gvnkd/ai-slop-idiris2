# TUI Job Monitor — Implementation Plan

**Sprint**: Interface Sprint (Mock Data)
**Based On**: `plans/tui_srd.md` v1.0
**Libraries**: idris2-tui (Base mainloop), idris2-async (deferred to backend sprint)

---

## 1. Architecture Overview

```
src/Monitor/Types.idr    — Display types and application state
src/Monitor/Mock.idr     — Mock data provider functions (plain IO)
src/Monitor/View.idr     — View instances for all TUI types
src/Monitor/Handler.idr  — Event handler (keyboard navigation)
src/Monitor/Main.idr     — TUI application entry point (replaces Main.idr for TUI)
```

**Mainloop choice**: `TUI.MainLoop.Base` with `HSum [Key]` events. No async needed for mock data. The async mainloop (`TUI.MainLoop.Async`) will be integrated during the backend sprint when real `Channel Result` data arrives.

**Pattern**: Direct `View` + `Event.Handler` (not Component). Our `JobMonitorState` is the single `stateT`. We call `runView` from `TUI.MainLoop`.

---

## 2. Dependency & Build Setup

### 2.1 Update `mon.ipkg`

The existing `mon.ipkg` needs to be updated to reference the new module structure and TUI dependencies.

**Changes**:
- Add `sourcedir = "src"` (currently `"build_src"`)
- Add dependency on `ansi` (required by `TUI.Painting`)
- Add all new `Monitor.*` modules to the `modules` list
- Keep `contrib`, `linear`, `json`, `elab-util` from `amon.ipkg`
- Add `tui` dependency

```
depends = base >= 0.5.1
        , contrib
        , linear
        , json
        , elab-util
        , ansi

modules = Protocol
        , Worker
        , Monitor.Types
        , Monitor.Mock
        , Monitor.View
        , Monitor.Handler
        , Monitor.Main
```

### 2.2 Dependency Chain

Already configured in `flake.nix`:
- `tui` depends on `ansi`, `elab-util`, `json`, `parser`, `bytestring`, etc.
- `tui-async` is available for future use
- `pack.toml` already lists `tui` and `ansi`

---

## 3. Module-by-Module Implementation

### 3.1 `src/Monitor/Types.idr` — Display Types & State

**Purpose**: Define all TUI-specific types that wrap existing domain types.

**Imports**: `public Protocol` (for `ProcessTask`, `TaskState`)

**Types to define**:

```idris
data JobDisplayStatus = QUEUED | RUNNING | SUCCESS | FAILED
```
- Maps from `TaskState` via `toDisplayStatus : TaskState -> JobDisplayStatus`
- QUEUED ← Ready, RUNNING ← InProgress, SUCCESS ← Done, FAILED ← Failed

```idris
record LogLine where
  constructor MkLogLine
  stream : String   -- "stdout>" or "stderr>"
  text   : String
```

```idris
record JobEntry where
  constructor MkJobEntry
  task   : ProcessTask
  status : JobDisplayStatus
```

```idris
record JobMonitorState where
  constructor MkJobMonitorState
  jobs      : List JobEntry    -- all jobs for left column
  selected  : Nat              -- index into jobs list
  logLines  : List LogLine     -- logs for currently selected job
  logOffset : Nat              -- scroll position in log viewer
```

**Helper functions**:
- `getSelectedJob : JobMonitorState -> Maybe JobEntry` — safe index into jobs list
- `initialState : List JobEntry -> JobMonitorState` — constructor with defaults (selected=0, logOffset=0, logLines=[])

**Verification**: Type-checks against `Protocol.idr` types. No TUI library imports needed.

---

### 3.2 `src/Monitor/Mock.idr` — Mock Data Providers

**Purpose**: Plain IO functions returning hardcoded data. Replaceable by channel-based providers.

**Imports**: `Monitor.Types`, `Protocol`

**Functions**:

```idris
loadMockJobs : IO (List JobEntry)
```
- Returns 4–6 mock `JobEntry` values using `MKProcessTask` from `tasks.json` data
- Mix of all four `JobDisplayStatus` values for visual testing
- Example entries: "List Root Directory" (SUCCESS), "Quick Sleep" (SUCCESS), "Timed Out Task" (FAILED), "Missing Binary Test" (QUEUED), "Health Check" (RUNNING)

```idris
loadMockLogs : JobEntry -> IO (List LogLine)
```
- Returns hardcoded log lines based on the job's status
- SUCCESS jobs: 15–20 lines of realistic stdout output
- FAILED jobs: 5 lines of stderr + error message
- QUEUED jobs: empty list (right column shows placeholder)
- RUNNING jobs: 8–10 lines of partial stdout (simulating in-progress)
- Each `LogLine` has stream prefix: `"stdout>"` or `"stderr>"`

**Edge case coverage**:
- One job with very long name (> 30 chars) to test truncation
- One job with empty logs to test placeholder display
- At least 30+ log lines for one job to test scroll behavior

**Verification**: Functions are plain `IO`, no TUI imports. Callable from REPL.

---

### 3.3 `src/Monitor/View.idr` — View Instances

**Purpose**: Implement `View` interface for all display types. This is the rendering layer.

**Imports**: `TUI.View`, `TUI.Painting`, `TUI.Geometry`, `TUI.Layout`, `Monitor.Types`, `Protocol`

#### 3.3.1 `View JobDisplayStatus`

- `size _ = MkArea 3 1` — badge is 3 chars wide (`[Q]`, `[R]`, `[✓]`, `[✗]`)
- `paint`:
  - QUEUED: `sgr [SetForeground Yellow]` then `showTextAt window.nw "[Q]"`
  - RUNNING: `sgr [SetForeground Blue]` then `showTextAt window.nw "[R]"`
  - SUCCESS: `sgr [SetForeground Green]` then `showTextAt window.nw "[\x2713]"` (checkmark)
  - FAILED: `sgr [SetForeground Red]` then `showTextAt window.nw "[\x2717]"` (ballot X)
  - Always finish with `sgr [Reset]`

**Note on ANSI colors**: The SRD specifies codes 33, 34, 92, 91. The `Text.ANSI` library provides `Yellow`, `Blue`, `BrightGreen`, `BrightRed` constructors for `SGR`. We should use those standard constructors. If `BrightGreen`/`BrightRed` are not available, fall back to `Green`/`Red`.

#### 3.3.2 `View JobEntry`

- `size entry = MkArea (badgeWidth + 1 + nameWidth) 1` where badgeWidth=3, nameWidth = `length entry.task.name`
- `paint`: Render as `"<badge> <name>"`
  - Paint the badge using `View JobDisplayStatus` (via `packLeft`)
  - Then paint the job name as a `String`
  - Truncate name if wider than window: take `(window.width - 4)` chars + "..."

#### 3.3.3 `View LogLine`

- `size line = MkArea (length line.stream + 1 + length line.text) 1`
- `paint`:
  - Paint stream prefix in `Cyan` or `Magenta` (stdout vs stderr)
  - Then paint text content
  - Wrap at window boundary (simple: just let text clip, as library doesn't enforce bounds)

#### 3.3.4 `View JobMonitorState` (Main Layout)

This is the most complex View instance. It renders the entire screen.

- `size _ = MkArea 80 24` (nominal terminal size, actual size provided by window rect)
- `paint state window st`:
  1. **Header**: Split top 1 row for title bar
     - `packTop Normal window "Job Monitor"` — paint centered or left-aligned title
     - Optionally paint an `HRule` separator
  2. **Split remaining area** into left (30%) and right (70%) columns:
     - `let leftWidth = window.width * 3 `div` 10`
     - `let (left, right) = remaining.splitLeft leftWidth`
  3. **Left column** (Job List):
     - If `st.jobs` is empty: paint "No jobs available" message
     - Otherwise: iterate through jobs with index, painting each as `JobEntry`
     - Selected job gets `Focused` state; all others get `State.demoteFocused state`
     - Use `packTop` for each job entry, advancing position downward
     - Handle vertical overflow: only render visible entries based on window height
  4. **Vertical separator**: paint `VRule` between columns (optional, 1 char)
  5. **Right column** (Log Viewer):
     - If selected job has no logs: paint "No log output" placeholder
     - Otherwise: render `st.logLines` starting from `st.logOffset`
     - Use `packTop` for each line
     - Only render as many lines as fit in the window height

**Implementation approach for left column**:
```idris
paintJobList : State -> Rect -> List JobEntry -> Nat -> Context ()
```
Recursive helper that tracks current index, applying `Focused` only when index == selected.

**Implementation approach for right column**:
```idris
paintLogViewer : State -> Rect -> List LogLine -> Nat -> Context ()
```
Skip `logOffset` lines from the start, then paint remaining lines that fit.

---

### 3.4 `src/Monitor/Handler.idr` — Event Handler

**Purpose**: Handle keyboard events, update application state.

**Imports**: `TUI.Event`, `TUI.Key`, `Data.List.Quantifiers`, `Monitor.Types`, `Monitor.Mock`

**Type**: `Event.Handler JobMonitorState () (HSum [Key])`
- This is: `HSum [Key] -> JobMonitorState -> IO (Either JobMonitorState (Maybe ()))`

**Handler function**:

```idris
onEvent : HSum [Key] -> JobMonitorState -> IO (Either JobMonitorState (Maybe ()))
```

**Key mappings**:

| Key | Action |
|-----|--------|
| `Here Up` | `selected` ← `max 0 (selected - 1)`, reload logs for new selection |
| `Here Down` | `selected` ← `min (length jobs - 1) (selected + 1)`, reload logs |
| `Here (Alpha 'q')` | Exit (`Result.exit`) |
| `Here Escape` | Exit (`Result.exit`) |
| `Here (Alpha 'j')` | Alternative: scroll log down by 1 line |
| `Here (Alpha 'k')` | Alternative: scroll log up by 1 line |
| `_` | Ignore (`Result.ignore`) |

**PageUp/PageDown limitation**: The idris2-tui `Key` type does not include PageUp/PageDown. The ANSI decoder only handles basic arrow keys. Options:
1. **Recommended for this sprint**: Use `j`/`k` for single-line log scroll, or use `Ctrl+U`/`Ctrl+D` style alternatives. Document the limitation.
2. **Future enhancement**: Extend the DFA in `TUI.Key` to decode `\ESC[5~` (PageUp) and `\ESC[6~` (PageDown).

**Handler implementation for job selection change**:
When selected index changes, call `loadMockLogs` to get logs for the newly selected job. Since `loadMockLogs` is `IO`, use `Result.run`:
```idris
onEvent (Here Up) st = case getSelectedJob {selected := max 0 (st.selected - 1)} st of
  Just entry => run $ do
    logs <- loadMockLogs entry
    pure $ { selected := max 0 (st.selected - 1)
           , logLines := logs
           , logOffset := 0 } st
  Nothing => ignore
```

**Log scrolling**: Update `logOffset` by page size (window height - header height). Since we don't have window size in the handler, use a fixed page size (e.g., 20 lines) or track it in state.

**State enrichment for scroll**: Consider adding `logPageSize : Nat` to `JobMonitorState`, or compute it as `max 1 (length logLines - logOffset)` during rendering.

---

### 3.5 `src/Monitor/Main.idr` — Entry Point

**Purpose**: Initialize state, enter mainloop.

**Imports**: `TUI.MainLoop`, `TUI.MainLoop.Base`, `TUI.MainLoop.Default`, `Monitor.Types`, `Monitor.Mock`, `Monitor.View`, `Monitor.Handler`

**Entry point**:

```idris
covering
run : IO ()
run = do
  jobs <- loadMockJobs
  let initState = initialState jobs
  -- Load initial logs for first selected job
  initState <- case getSelectedJob initState of
    Just entry => do
      logs <- loadMockLogs entry
      pure $ { logLines := logs } initState
    Nothing => pure initState
  ignore $ runView base onEvent initState
```

```idris
covering
main : IO ()
main = run
```

**Mainloop selection**:
- `base : Base` — the `()` unit value, `MainLoop Base (HSum [Key])` instance
- `runView` calls `runRaw` which: enters raw mode, alt screen, hides cursor, loops reading keys and rendering
- Alternative: use `getDefault` from `TUI.MainLoop.Default` (auto-selects between Base and InputShim)

---

## 4. Build Verification Procedure

After completing **each** task below, run:

```
nix develop --command bash -c 'idris2 --build amon.ipkg' 2>&1
```

This verifies that all modules compile together. If there are compilation errors, **fix them before proceeding to the next task**. The `amon.ipkg` must be kept in sync with the new modules as they are added (update the `modules` list incrementally).

---

## 5. Implementation Order (Tasks)

Execute in this order. Each step must pass the build verification above before moving on.

### Task 1: Scaffold module structure
- Create `src/Monitor/` directory
- Create all 5 `.idr` files with module declarations and imports
- Update `amon.ipkg`: add new `Monitor.*` modules to the `modules` list, add `ansi` to `depends`
- **Verify build**: `nix develop --command bash -c 'idris2 --build amon.ipkg' 2>&1`
- Fix any compilation errors before proceeding

### Task 2: Implement `Monitor.Types`
- Define `JobDisplayStatus`, `toDisplayStatus`
- Define `LogLine`, `JobEntry`
- Define `JobMonitorState`
- Define helper functions (`getSelectedJob`, `initialState`)
- **Verify build**: `nix develop --command bash -c 'idris2 --build amon.ipkg' 2>&1`
- Fix any compilation errors before proceeding

### Task 3: Implement `Monitor.Mock`
- Implement `loadMockJobs` with 4–6 realistic entries
- Implement `loadMockLogs` with varied content per status
- **Verify build**: `nix develop --command bash -c 'idris2 --build amon.ipkg' 2>&1`
- Fix any compilation errors before proceeding

### Task 4: Implement `View JobDisplayStatus` and `View JobEntry` (in `Monitor.View`)
- Start with `JobDisplayStatus` — verify colors render
- Then `JobEntry` — verify badge + name rendering
- **Verify build**: `nix develop --command bash -c 'idris2 --build amon.ipkg' 2>&1`
- Fix any compilation errors before proceeding

### Task 5: Implement `View LogLine` (in `Monitor.View`)
- Straightforward: prefix + text
- **Verify build**: `nix develop --command bash -c 'idris2 --build amon.ipkg' 2>&1`
- Fix any compilation errors before proceeding

### Task 6: Implement `View JobMonitorState` (in `Monitor.View`)
- Full two-column layout
- Header bar
- Job list with selection highlight
- Log viewer with scroll offset
- This is the most complex step — iterate carefully
- **Verify build**: `nix develop --command bash -c 'idris2 --build amon.ipkg' 2>&1`
- Fix any compilation errors before proceeding

### Task 7: Implement `Monitor.Handler`
- Arrow key navigation
- Q/Escape exit
- Log scroll (j/k or alternative)
- Job selection change with log reload
- **Verify build**: `nix develop --command bash -c 'idris2 --build amon.ipkg' 2>&1`
- Fix any compilation errors before proceeding

### Task 8: Implement `Monitor.Main`
- Wire everything together
- `runView base onEvent initState`
- **Verify build**: `nix develop --command bash -c 'idris2 --build amon.ipkg' 2>&1`
- Fix any compilation errors before proceeding

### Task 9: Update build configuration (final check)
- Ensure `amon.ipkg` modules list and depends are complete and correct
- Ensure `mon.ipkg` is also updated if needed
- **Verify build**: `nix develop --command bash -c 'idris2 --build amon.ipkg' 2>&1`
- Fix any compilation errors before proceeding

### Task 10: Edge case polish
- Empty job list message
- Empty log placeholder
- Long job name truncation
- Selection boundary clamping
- **Verify build**: `nix develop --command bash -c 'idris2 --build amon.ipkg' 2>&1`
- Fix any compilation errors before proceeding
- Visual verification of all acceptance criteria

---

## 5. Key Technical Decisions

### 5.1 Base vs Async Mainloop

**Decision**: Use `TUI.MainLoop.Base` for this sprint.

**Rationale**:
- Mock data is synchronous — no channels or async I/O needed
- Base mainloop has simpler setup and fewer dependencies
- Async mainloop requires `idris2-async`, epoll, and complex fiber management
- Backend sprint will migrate to `TUI.MainLoop.Async` when wiring `Channel Result`

**Migration path** (backend sprint):
- Change `base` → `asyncMain [jobEventSource resultsChan]`
- Event type changes from `HSum [Key]` → `HSum [Key, JobUpdate, LogChunk]`
- Handler expands to handle new event types via `Event.union`
- View instances remain unchanged

### 5.2 PageUp/PageDown

**Decision**: Use `j`/`k` for line-by-line log scroll in this sprint.

**Rationale**: The idris2-tui `Key` type and ANSI decoder don't support PageUp/PageDown escape sequences (`\ESC[5~`, `\ESC[6~`). Extending the library's DFA is out of scope.

**Migration path**: Extend `TUI.Key` with `PageUp | PageDown` constructors and add DFA transitions in `TUI.Key.ansiDecoder`.

### 5.3 Direct View vs Component

**Decision**: Use `View JobMonitorState` directly with `runView`, not Component.

**Rationale**:
- The app has a single unified state (no sub-components to compose)
- Component abstraction adds complexity (Response type, push/yield mechanics) without benefit here
- VList could be used for the job list but doesn't support our custom badge rendering well
- Direct View gives full control over layout

### 5.4 Log Scroll State

**Decision**: Store `logOffset : Nat` in `JobMonitorState`. Use fixed page size (20 lines).

**Rationale**: Window dimensions are not available in the event handler (only in paint). A fixed page size is simpler and sufficient for mock data. Backend sprint can add dynamic page size tracking.

### 5.5 Color Strategy

**Decision**: Use `Text.ANSI` SGR constructors (`Yellow`, `Blue`, `Green`, `Red`) for maximum compatibility.

**Rationale**: The SRD specifies ANSI codes 33, 34, 92, 91. Bright variants may not be available on all terminals. We'll use standard 16-color variants and document the difference. The `Text.ANSI` library's `SetForeground` with `Yellow`, `Blue`, `Green`, `Red` maps to codes 33, 34, 32, 31 respectively.

---

## 6. File Dependency Graph

```
Protocol.idr ─────────────────────────────┐
                                           │
Monitor.Types.idr ◄───────────────────────┘
       │
       ├──► Monitor.Mock.idr
       │
       ├──► Monitor.View.idr ◄── TUI.* (View, Painting, Geometry, Layout)
       │         │
       │         └──► Monitor.Handler.idr ◄── TUI.Event, TUI.Key
       │                       │
       │                       └──► Monitor.Main.idr ◄── TUI.MainLoop.Base
       │
       └──► (unchanged) Worker.idr, Main.idr
```

---

## 7. Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| `Key` type missing PageUp/PageDown | Cannot implement IR-032/IR-033 as specified | Use j/k alternatives; document limitation |
| No clipping/scrolling in idris2-tui | VList notes this as a known gap | Implement manual offset-based rendering (skip off-screen lines) |
| View bounds not enforced by library | Text can overflow column boundaries | Manual truncation with ellipsis in paint implementations |
| `View String` instance may conflict | Idris may pick wrong instance | Use explicit `paint @{...}` if needed |
| Raw mode may not work in all terminals | App won't start | Test in multiple terminals; use InputShim as fallback |
| Synchronous update not supported | Screen flicker | Acceptable for mock sprint; optimize in backend sprint |

---

## 8. Acceptance Criteria Mapping

| Criterion | Implementation Location | Verification |
|-----------|------------------------|--------------|
| AC-1: Two columns | `View JobMonitorState` in `Monitor.View.idr` | Visual inspection |
| AC-2: Mock jobs in left column | `paint` for job list + `loadMockJobs` | Visual inspection |
| AC-3: Color-coded status | `View JobDisplayStatus` with `sgr` | Visual inspection |
| AC-4: Selection → log update | `Monitor.Handler` reloads logs on selection change | Navigate jobs, verify |
| AC-5: Up arrow | `onEvent (Here Up)` in `Monitor.Handler` | Press key, observe |
| AC-6: Down arrow | `onEvent (Here Down)` in `Monitor.Handler` | Press key, observe |
| AC-7: Log scroll up | `onEvent (Here (Alpha 'k'))` | Press key, observe |
| AC-8: Log scroll down | `onEvent (Here (Alpha 'j'))` | Press key, observe |
| AC-9: Q/Escape exit | `onEvent (Here (Alpha 'q'))` / `onEvent (Here Escape)` | Press key, verify exit |
| IC-1: JobDisplayStatus maps from TaskState | `toDisplayStatus` in `Monitor.Types.idr` | Type-checking |
| IC-2: JobEntry wraps ProcessTask | Record definition in `Monitor.Types.idr` | Code review |
| IC-3: View instances defined | `Monitor.View.idr` | Type-checking |
| IC-4: Handler type matches | `Monitor.Handler.idr` | Type-checking |
| IC-5: Mock providers are plain IO | `Monitor.Mock.idr` | Code review |
| IC-6: UI depends only on domain types | All Monitor.* modules | Code review: no Worker.idr imports |

---

## 9. Future Sprint Integration Points

These are documented here for continuity but NOT implemented in this sprint:

### 9.1 Backend Event Types (for `HSum [Key, JobUpdate, LogChunk]`)

```idris
data JobUpdate  = JobStarted ProcessTask | JobFinished ProcessTask Worker.Result
data LogChunk   = MkLogChunk ProcessTask (List LogLine)
```

### 9.2 EventSource for Channel Result

```idris
jobEventSource : Channel Worker.Result -> EventSource [Key, JobUpdate, LogChunk]
```

### 9.3 Mainloop Migration

Change from:
```idris
runView base onEvent initState
```
To:
```idris
runView (asyncMain [jobEventSource resultsChan]) onEvent initState
```

### 9.4 Config Loading

Replace `loadMockJobs` with `loadTasks "tasks.json"` + initial status mapping.

### 9.5 Real Log Reading

Replace `loadMockLogs` with reading from `ProcessTask.logFile` path.

---

## 10. Estimated Effort

| Task | Estimated Complexity | Notes |
|------|---------------------|-------|
| Task 1: Scaffold | Low | Directory + stub files |
| Task 2: Types | Low | Straightforward record/enum definitions |
| Task 3: Mock | Low | Hardcoded data, plain IO |
| Task 4: View (Status + Entry) | Medium | First interaction with TUI painting API |
| Task 5: View (LogLine) | Low | Simple text rendering |
| Task 6: View (Full Layout) | **High** | Two-column layout, selection, scroll offset — most complex step |
| Task 7: Handler | Medium | State updates with IO reload, boundary clamping |
| Task 8: Main | Low | Glue code, runView call |
| Task 9: Build config | Low | ipkg updates |
| Task 10: Polish | Medium | Edge cases, visual tuning |

**Total**: ~10 focused implementation sessions.

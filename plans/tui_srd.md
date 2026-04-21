# Software Requirements Document (SRD)

## TUI Job Monitor Application — Interface Sprint

**Document Version**: 1.0  
**Date**: January 2025  
**Author**: [Author Name]  
**Status**: Draft  

---

## Table of Contents

1. [Introduction](#1-introduction)
2. [Purpose](#2-purpose)
3. [Scope](#3-scope)
4. [Definitions, Acronyms, and Abbreviations](#4-definitions-acronyms-and-abbreviations)
5. [Overall Description](#5-overall-description)
6. [Specific Requirements](#6-specific-requirements)
7. [Interface Requirements](#7-interface-requirements)
8. [Non-Functional Requirements](#8-non-functional-requirements)
9. [Acceptance Criteria](#9-acceptance-criteria)
10. [Appendix](#10-appendix)

---

## 1. Introduction

This document describes the software requirements for a Text User Interface (TUI) **shell** for a job monitoring application. The interface will be implemented in the Idris2 programming language using idris2-tui and idris2-async libraries.

> **Note**: This specification covers only the visual interface layer. Backend logic, data providers, and worker process management will be addressed in a subsequent sprint.

---

## 2. Purpose

The purpose of this document is to:

- Define clear and unambiguous requirements for the TUI interface components
- Provide a basis for agreement between stakeholders on the UI deliverables
- Serve as a reference for validation testing and quality assurance
- Guide the development team in implementing the interface layer independently

---

## 3. Scope

### 3.1 In Scope (Interface Sprint)

- Design and implementation of a two-column TUI layout
- Mock data display mechanism for job list (left column)
- Mock data display mechanism for log output viewer (right column)  
- Keyboard navigation for selection and scrolling
- Visual styling with color-coded status indicators
- Interface contract definitions for future backend integration

### 3.2 Out of Scope (Deferred to Backend Sprint)

- Loading job definitions from configuration files
- Actual worker process spawning or management
- Real-time status updates from running jobs
- Capturing stdout/stderr streams from processes
- Any network communication or IPC mechanisms
- Job scheduling logic or queue management

---

## 4. Definitions, Acronyms, and Abbreviations

| Term | Definition |
|------|------------|
| **TUI** | Text User Interface — a terminal-based user interface |
| **ProcessTask** | Existing record type in `Protocol.idr` representing a job definition (name, path, args, timeout, logFile) |
| **TaskState** | Existing enum in `Protocol.idr`: `Ready \| InProgress \| Done \| Failed` |
| **Ticket** | Existing state-indexed type in `Protocol.idr` tracking job lifecycle |
| **Result** | Existing type in `Worker.idr`: `Success String String \| Failure String String` |
| **JobEntry** | TUI display wrapper: `ProcessTask` + `JobDisplayStatus` |
| **LogLine** | A line of log text with stream indicator, associated with a job |
| **JobDisplayStatus** | Visual status: QUEUED, RUNNING, SUCCESS, FAILED — maps from `TaskState` |
| **idris2-tui** | Idris2 library for building terminal user interfaces |
| **idris2-async** | Idris2 library for asynchronous programming |
| **View** | idris2-tui interface: `size` + `paint` for rendering types to the terminal |
| **Component** | idris2-tui record: opaque UI element wrapping state, handler, and View |
| **Event.Handler** | idris2-tui function type: `eventT -> stateT -> IO (Either stateT (Maybe valueT))` |
| **EventSource** | idris2-tui async concept: function posting events to a channel-based queue |

---

## 5. Overall Description

### 5.1 System Context

The application runs in a terminal environment as a standalone TUI component. It displays mock/placeholder data during this sprint, with an interface contract prepared for future connection to actual job management logic.

```
┌─────────────────────────────────────────────────────┐
│                   TUI Application                    │
│                                                      │
│  ┌──────────────────┐  ┌─────────────────────────┐  │
│  │                  │  │                         │  │
│  │   Job List       │  │     Log Output          │  │
│  │   (Left Column)  │  │     (Right Column)      │  │
│  │                  │  │                         │  │
│  └──────────────────┘  └─────────────────────────┘  │
│                                                      │
└─────────────────────────────────────────────────────┘
```

### 5.2 Architecture Note

The TUI layer will be designed with the following separation:

```
┌────────────────────────────────────────────────────────────┐
│                    TUI Layer (THIS SPRINT)                  │
│                                                             │
│   ┌──────────────┐    View / Component     ┌───────────┐   │
│   │  JobMonitor  │    interface contracts   │  Mock     │   │
│   │  State       │◄────────────────────────►│  Provider │   │
│   │  + Handlers  │   (plain IO functions)   │  Funcs    │   │
│   └──────────────┘                          └───────────┘   │
│          │                                                  │
│     Event.Handler                                          │
│     + View instances                                       │
│     + Layout (packLeft / packRight)                        │
│                                                             │
└────────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────────┐
│                  Backend Layer (NEXT SPRINT)                │
│                                                             │
│   ┌──────────────┐    Channel Task/Result   ┌───────────┐  │
│   │  Job Manager │◄────────────────────────►│  Worker   │  │
│   │  & Config    │   (existing pattern      │  Pool     │  │
│   │              │    from Worker.idr)       │           │  │
│   └──────────────┘                          └───────────┘  │
└────────────────────────────────────────────────────────────┘
```

### 5.3 Existing Codebase Integration

The TUI integrates with the following existing modules:

| Module | Role | TUI Usage |
|--------|------|-----------|
| `Protocol.idr` | Defines `ProcessTask`, `TaskState`, `Ticket` | TUI wraps `ProcessTask` in `JobEntry` with display status; maps `TaskState` → `JobDisplayStatus` |
| `Worker.idr` | Defines `Result`, `Task`, worker loop | Backend contract: `Channel Result` feeds job updates into TUI via `EventSource` |
| `Main.idr` | Entry point, `spawnPool`, `loadTasks` | Future: TUI main replaces direct `main`; calls `spawnPool` and wires channels into async event sources |

### 5.4 User Characteristics

- Primary users: System administrators and DevOps engineers (future)
- Users are expected to have basic terminal navigation knowledge
- No graphical desktop environment is required

---

## 6. Specific Requirements

### 6.1 Functional Requirements (Interface Only)

| ID | Requirement | Priority | Notes |
|----|-------------|----------|-------|
| FR-001 | The interface shall define a `JobDisplayStatus` type mapping from existing `TaskState` for visual representation | Must | Reuses Protocol.idr types |
| FR-002 | The interface shall define `JobEntry` wrapping existing `ProcessTask` with display metadata | Must | Extends, does not replace, domain types |
| FR-003 | The interface shall define `LogLine` with stream origin indicator | Must | For right column display |
| FR-004 | The interface shall define `JobMonitorState` as the TUI application state record | Must | Compatible with idris2-tui `View` and `Component` |
| FR-005 | The application shall provide mock data via plain `IO` functions (`loadMockJobs`, `loadMockLogs`) | Must | Replaceable by channel-based providers in backend sprint |
| FR-006 | The application shall implement `View` instances for `JobDisplayStatus`, `JobEntry`, `LogLine`, and `JobMonitorState` | Must | Follows idris2-tui rendering pattern |
| FR-007 | The application shall define an event handler matching `Event.Handler JobMonitorState () (HSum [Key])` | Must | Follows idris2-tui event handling pattern |
| FR-008 | The interface shall define a backend integration contract using `Channel Result` and `EventSource` | Must | Matches existing Worker.idr channel pattern |

### 6.2 Status Display Definitions

For demonstration purposes, the following statuses shall be supported visually:

| Status | Maps From (`TaskState`) | Description | Color Code | Visual Badge |
|--------|-------------------------|-------------|------------|--------------|
| **QUEUED** | `Ready` | Placeholder for scheduled jobs | Yellow (33) | `[Q]` |
| **RUNNING** | `InProgress` | Placeholder for active jobs | Blue (34) | `[R]` |
| **SUCCESS** | `Done` | Placeholder for completed jobs | Bright Green (92) | `[✓]` |
| **FAILED** | `Failed` | Placeholder for failed jobs | Bright Red (91) | `[✗]` |

### 6.3 Deferred Requirements (Not in This Sprint)

The following requirements are documented for reference but **not implemented** in this sprint:

| ID | Requirement | Will Be Implemented In |
|----|-------------|------------------------|
| FR-D01 | Load job definitions from `tasks.json` configuration source at startup | Backend Sprint |
| FR-D02 | Track and update job status in real-time via `Channel Result` | Backend Sprint |
| FR-D03 | Capture stdout/stderr output as produced by worker processes | Backend Sprint |
| FR-D04 | Wire `EventSource` for async job/log updates into TUI mainloop | Backend Sprint |

---

## 7. Interface Requirements

### 7.1 Layout Requirements

| ID | Requirement | Details |
|----|-------------|---------|
| IR-001 | Two-column layout | Left column: job list; Right column: log viewer |
| IR-002 | Column width ratio | Configurable, default 30% / 70% split via `splitLeft` |
| IR-003 | Vertical alignment | Both columns shall span the full terminal height minus header |
| IR-004 | Header area | Title bar displaying "Job Monitor" or similar |

### 7.2 Left Column: Job List

| ID | Requirement | Details |
|----|-------------|---------|
| IR-010 | Job entry display | Show job name and status badge via `View JobEntry` instance |
| IR-011 | Status indication | Color-coded text badge via `View JobDisplayStatus` instance |
| IR-012 | Selection highlight | Inverse video or distinct background for selected job (via `View.State.Focused`) |
| IR-013 | Scroll support | Handle overflow via keyboard navigation |

### 7.3 Right Column: Log Viewer

| ID | Requirement | Details |
|----|-------------|---------|
| IR-020 | Output display | Show log text lines with stream indicator prefix via `View LogLine` instance |
| IR-021 | Stream indication | Prefix each line with `stdout>` or `stderr>` (for mock data) |
| IR-022 | Text wrapping | Wrap long lines at column boundary |
| IR-023 | Scroll position | Maintain scroll position when switching jobs |

### 7.4 Keyboard Navigation

| ID | Requirement | Key | Action |
|----|-------------|-----|--------|
| IR-030 | Move selection up | `↑` (Up Arrow) | Select previous job in list |
| IR-031 | Move selection down | `↓` (Down Arrow) | Select next job in list |
| IR-032 | Scroll log up | `PageUp` | Move log view up by one page |
| IR-033 | Scroll log down | `PageDown` | Move log view down by one page |
| IR-034 | Exit application | `Q` or `Escape` | Close the application gracefully |

### 7.5 Visual Design

| ID | Requirement | Details |
|----|-------------|---------|
| IR-040 | Color scheme | Use terminal-compatible ANSI colors (16-color minimum) |
| IR-041 | Status colors | As defined in Section 6.2 |
| IR-042 | Selected item | Highlight with distinct background color or inverse video |

---

## 8. Non-Functional Requirements

### 8.1 Performance

| ID | Requirement | Target |
|----|-------------|--------|
| NFR-001 | UI responsiveness | Key input shall be processed within 100ms |
| NFR-002 | Log rendering | Shall handle logs up to 10,000 lines without degradation |

### 8.2 Reliability

| ID | Requirement | Details |
|----|-------------|--------|
| NFR-010 | Graceful handling | Application shall not crash on missing or empty data |
| NFR-011 | Buffer management | Log buffer shall be bounded to prevent memory exhaustion |

### 8.3 Portability

| ID | Requirement | Details |
|----|-------------|--------|
| NFR-020 | Terminal compatibility | Shall work in standard Unix terminals and Windows Terminal |
| NFR-021 | UTF-8 support | Shall correctly display Unicode characters |

### 8.4 Extensibility (Interface Contract)

| ID | Requirement | Details |
|----|-------------|--------|
| NFR-030 | Mock provider functions | Define `loadMockJobs : IO (List JobEntry)` and `loadMockLogs : ProcessTask -> IO (List LogLine)` as plain IO functions |
| NFR-031 | Swappable providers | Mock functions shall be replaceable by channel-based providers without View/Handler changes |
| NFR-032 | Backend event contract | Define `JobUpdate` and `LogChunk` event types for `EventSource` integration via `HSum [Key, JobUpdate, LogChunk]` |

---

## 9. Acceptance Criteria

### 9.1 Functional Acceptance (Interface Sprint)

| # | Criterion | Validation Method |
|---|-----------|-------------------|
| AC-1 | Application displays two distinct columns in the terminal | Visual inspection |
| AC-2 | Mock job entries appear in the left column | Run application, verify display |
| AC-3 | Each job shows color-coded status indicator | Verify badge colors match specification |
| AC-4 | Selected job triggers log display update in right column | Navigate jobs, verify log changes |
| AC-5 | Up arrow moves selection to previous job | Press key, observe cursor movement |
| AC-6 | Down arrow moves selection to next job | Press key, observe cursor movement |
| AC-7 | PageUp scrolls log content upward | Scroll up in long log, verify content change |
| AC-8 | PageDown scrolls log content downward | Scroll down in log, verify content change |
| AC-9 | Q or Escape closes the application gracefully | Press key, verify clean exit |

### 9.2 Visual Checkpoints

1. **Initial State**: Two columns visible with header, first job selected and highlighted
2. **Selection Movement**: Cursor visibly moves between jobs on arrow key press
3. **Status Badges**: Each status type displays correct color and badge text
4. **Log Scrolling**: Smooth page-by-page movement without flicker

### 9.3 Interface Contract Validation

| # | Criterion | Validation Method |
|---|-----------|-------------------|
| IC-1 | `JobDisplayStatus` maps correctly from `TaskState` | Code inspection + type-checking |
| IC-2 | `JobEntry` wraps existing `ProcessTask` without duplication | Code inspection |
| IC-3 | `View` instances defined for `JobDisplayStatus`, `JobEntry`, `LogLine`, `JobMonitorState` | Type-checking passes |
| IC-4 | Event handler matches `Event.Handler JobMonitorState () (HSum [Key])` | Type-checking passes |
| IC-5 | Mock providers (`loadMockJobs`, `loadMockLogs`) are plain IO functions | Code review |
| IC-6 | UI code depends only on domain types (`ProcessTask`, `TaskState`), not concrete backend implementations | Code review |

### 9.4 Edge Cases (Interface)

| Scenario | Expected Behavior |
|----------|-------------------|
| No jobs in mock data | Display "No jobs available" message in left column |
| Empty log for job | Right column shows placeholder or remains blank |
| Very long job name | Truncate with ellipsis (`...`) at column boundary |
| Selection at boundaries | Up/Down keys wrap or stop (configurable behavior) |

---

## 10. Appendix

### A. Suggested Color Constants

| Status | ANSI Foreground Code |
|--------|---------------------|
| QUEUED | 33 (Yellow) |
| RUNNING | 34 (Blue) or 32 (Green) |
| SUCCESS | 92 (Bright Green) |
| FAILED | 91 (Bright Red) |

### B. Interface Contract Skeleton

```idris
-- ============================================================
-- B. Interface Contract Skeleton
-- ============================================================
-- Reuses existing domain types from Protocol.idr and Worker.idr,
-- and follows idris2-tui architectural patterns (View, Component,
-- Event.Handler) rather than type-class-based providers.
--
-- Module structure for the TUI interface sprint:
--   src/Protocol.idr        -- (existing) ProcessTask, TaskState, Ticket
--   src/Worker.idr           -- (existing) Result, Task
--   src/Monitor/Types.idr    -- TUI-specific display and state types
--   src/Monitor/Mock.idr     -- Mock data provider functions
--   src/Monitor/View.idr     -- View instances for TUI rendering
--   src/Monitor/Main.idr     -- TUI application entry point

-- ----------------------------------------------------------
-- 1. Display Status Mapping  (Monitor/Types.idr)
-- ----------------------------------------------------------

||| Visual display status for jobs in the TUI.
||| Maps internal TaskState to user-facing status.
public export
data JobDisplayStatus
  = QUEUED    -- Ready / not yet started
  | RUNNING   -- InProgress
  | SUCCESS   -- Done
  | FAILED    -- Failed (after retries exhausted)

||| Map from internal TaskState to display status.
public export
toDisplayStatus : TaskState -> JobDisplayStatus
toDisplayStatus Ready      = QUEUED
toDisplayStatus InProgress = RUNNING
toDisplayStatus Done       = SUCCESS
toDisplayStatus Failed     = FAILED

-- ----------------------------------------------------------
-- 2. TUI Data Types  (Monitor/Types.idr)
-- ----------------------------------------------------------

||| A log line with stream origin indicator.
public export
record LogLine where
  constructor MkLogLine
  stream : String    -- "stdout>" or "stderr>"
  text   : String

||| A job entry ready for display in the TUI.
||| Wraps the existing ProcessTask with display metadata.
public export
record JobEntry where
  constructor MkJobEntry
  task   : ProcessTask
  status : JobDisplayStatus

||| TUI application state for the job monitor.
||| This is the `stateT` parameter used with idris2-tui's
||| Component and View interfaces.
public export
record JobMonitorState where
  constructor MkJobMonitorState
  jobs      : List JobEntry
  selected  : Nat                   -- index of selected job
  logLines  : List LogLine          -- log output for selected job
  logOffset : Nat                   -- scroll position in log viewer

-- ----------------------------------------------------------
-- 3. Mock Data Provider Functions  (Monitor/Mock.idr)
-- ----------------------------------------------------------
-- Plain IO functions, NOT type class implementations.
-- Backend sprint replaces these with channel-based providers
-- matching the existing Channel Task / Channel Result pattern.

||| Load initial job entries (mock).
||| Backend contract: replace with loading from tasks.json
||| and mapping ProcessTask -> JobEntry via channel results.
public export
loadMockJobs : IO (List JobEntry)

||| Load log lines for a given job (mock).
||| Backend contract: replace with reading from the logFile
||| path specified in ProcessTask.logFile.
public export
loadMockLogs : ProcessTask -> IO (List LogLine)

-- ----------------------------------------------------------
-- 4. View Instances  (Monitor/View.idr)
-- ----------------------------------------------------------
-- These implement the idris2-tui View interface for rendering.
-- View has two methods: `size : selfT -> Area` and
-- `paint : State -> Rect -> selfT -> Context ()`

||| Status badge rendering: "[Q]" yellow, "[R]" blue, etc.
export
View JobDisplayStatus where
  size _ = MkArea 3 1
  paint state window QUEUED  = -- yellow "[Q]"
  paint state window RUNNING = -- blue   "[R]"
  paint state window SUCCESS = -- green  "[✓]"
  paint state window FAILED  = -- red    "[✗]"

||| Render a job entry as: "<badge> <name>"
export
View JobEntry where
  size entry   = MkArea (3 + length entry.task.name + 1) 1
  paint state window entry =
    -- paint badge, then job name, using Layout.packLeft

||| Render a log line as: "<stream> <text>"
export
View LogLine where
  size line    = MkArea (length line.stream + 1 + length line.text) 1
  paint state window line =
    -- paint stream prefix, then log text

||| Main application view: two-column layout.
||| Left column: job list (30% width).
||| Right column: log viewer (70% width).
export
View JobMonitorState where
  size state = ?fullTerminalArea
  paint focus window state = do
    let (left, right) = window.splitLeft (window.width `div` 10 * 3)
    -- paint job list into left
    -- paint log viewer into right

-- ----------------------------------------------------------
-- 5. Event Handler  (Monitor/Main.idr)
-- ----------------------------------------------------------
-- Follows idris2-tui's Event.Handler type:
--   eventT -> stateT -> IO (Either stateT (Maybe valueT))
-- Uses HSum [Key] for keyboard events, extensible for future
-- async events (e.g., HSum [Key, JobUpdate, LogChunk]).

public export
onEvent : Event.Handler JobMonitorState () (HSum [Key])
onEvent (Here Up)          st = update $ {selected $= max 0 (-1)} st
onEvent (Here Down)        st = update $ {selected $= (+1)} st
onEvent (Here (Alpha 'q')) _  = exit
onEvent (Here Escape)      _  = exit
onEvent _                  st = ignore

-- ----------------------------------------------------------
-- 6. Backend Integration Contract  (Future Sprint)
-- ----------------------------------------------------------
-- The backend sprint will integrate via the existing channel
-- pattern from Worker.idr and Main.idr:
--
--   Channel Task   -- sends ProcessTask to worker pool
--   Channel Result -- receives Success/Failure results
--
-- The async mainloop (TUI.MainLoop.Async) supports custom
-- EventSource types. Backend integration will add:
--
--   data JobUpdate
--     = JobStarted  ProcessTask
--     | JobFinished ProcessTask Result
--
--   data LogChunk
--     = MkLogChunk ProcessTask (List LogLine)
--
--   jobEventSource
--     : Channel Result
--     -> EventSource [Key, JobUpdate, LogChunk]
--     -- posts JobUpdate / LogChunk events to the TUI
--     -- event queue when results arrive on Channel Result
```

### C. Deferred Requirements Reference

For planning purposes, the following will be addressed in the Backend Sprint:

| Requirement | Description |
|-------------|-------------|
| Config Loading | Parse job definitions from `tasks.json` (existing `loadTasks` in `Main.idr`) |
| Process Management | Spawn and monitor worker processes using existing `spawnPool` / `Worker.idr` |
| Stream Capture | Route stdout/stderr to log buffers via `ProcessTask.logFile` |
| Real-time Updates | Wire `Channel Result` into TUI via `EventSource` and `HSum [Key, JobUpdate, LogChunk]` |

### D. References

- Idris2 Documentation: https://idris2docs.readthedocs.io
- idris2-tui library: https://github.com/emdash/idris2-tui
- idris2-async library: https://github.com/stefan-hoeck/idris2-async
- Existing project modules: `Protocol.idr`, `Worker.idr`, `Main.idr`

---

**End of Document**

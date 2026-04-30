# Codebase Analysis Report: amon

## Overview

This report analyzes the Idris 2 codebase of the `amon` project against the style
guide in `STYLE.md` and functional programming best practices, with particular
attention to Idris 2 idioms.

---

## Critical Issues

### 1. Massive Code Duplication: Process Spawning

**Files:** `Monitor/Process.idr`, `Monitor/ProcessStream.idr`, `PipeLeak.idr`

The same low-level POSIX process spawning logic is copy-pasted across three files:
- `Monitor/Process.spawnCmd`
- `Monitor/ProcessStream.spawnProcessSetup`
- `PipeLeak.spawn`

Each performs: `malloc` pipe array, `pipe`/`pipe2`, `newBuffer 8`, `getBits32`,
`fork`, child `dup2` dance, parent `fcntl` for `O_NONBLOCK`, `execvp "/bin/sh"`.

**Advice:** Extract a single `spawnProcess` function in `Monitor.Process` that
returns `IO (Maybe (Int, Int, Maybe Int))` --- (readFd, pid, logFd).
`ProcessStream` already imports `Monitor.Process`. The differences (`pipe` vs
`pipe2`, `closeFdsFrom 3`, env prefix) should be parameters or variants of this
single function. `PipeLeak.idr` should reuse it too.

### 2. Duplicated `loadTasks`

**Files:** `Main.idr` (lines 17-29), `Monitor/Provider.idr` (lines 10-22)

Identical implementation. `Main.idr` already imports `Monitor.Provider`, so this
is pure duplication.

**Fix:** Delete `Main.loadTasks` and use `Monitor.Provider.loadTasks`.

### 3. Duplicated Output Splitting

**Files:** `Monitor/Process.idr` (lines 174-183), `Monitor/ProcessStream.idr` (lines 150-158)

`splitOutput` and `splitOutputLocal` do the same thing: accumulate partial lines
from a string buffer. The `ProcessStream` version is slightly more efficient
(reverses once), but they should be one function.

---

## Style Violations (STYLE.md)

### Missing Documentation

STYLE.md: *"Document all exported top-level functions, interfaces, and data
types. This is the most important rule."*

Almost no exported function has a doc comment. `Protocol.idr`, `Monitor.Types.idr`,
`Monitor.Process.idr`, `Monitor.ProcessStream.idr` --- all exported, none documented.

### `mutual` Blocks

STYLE.md: *"Avoid `mutual` blocks. Declare signatures first, then definitions."*

**File:** `Monitor/Process.idr` (lines 202-240, 246-267)

Two `mutual` blocks for ANSI escape sequence parsing. The
`stripGo`/`handleCSI`/`skipOSC` trio and the
`truncGo`/`keepSgr`/`takeTrailingSgr` trio should be rewritten with forward
declarations.

### `primIO` Return Discipline

STYLE.md: *"`primIO` returns must be ignored when the result is not needed. Use
`ignore $ primIO ...`"*

**File:** `Monitor/Process.idr` lines 152-155

```idris
_ <- primIO $ prim__close readFd
_ <- primIO $ prim__dup2 writeFd 1
```

These use `_ <-` inside `do` instead of `ignore $ primIO ...`. The `_ <-`
pattern inside `do` blocks for `primIO` is specifically called out as problematic
in STYLE.md and AGENTS.md because it can cause `HasIO` resolution failures.

**File:** `Monitor/Process.idr` line 75-76

```idris
_ <- writeToFd fd chunk
pure ()
```

Redundant `pure ()`. Should be `ignore $ writeToFd fd chunk`.

**File:** `Monitor/Process.idr` lines 161, 118-119

Same pattern: `pure ()` after `when` or after `_ <-` is unnecessary noise.

### String Interpolation vs `++`

STYLE.md does not explicitly ban `++`, but the codebase heavily uses string
interpolation (`\{x}`) in some places and `++` in others, inconsistently.

**Verbose `++` patterns:**

- `Monitor/Process.idr` line 93:
  `"[END] " ++ ts ++ " " ++ statusStr ++ "\n"` ->
  `"[END] \{ts} \{statusStr}\n"`

- `Monitor/Process.idr` line 124:
  `"timeout " ++ show task.timeout ++ "s " ++ ...` ->
  `"timeout \{show task.timeout}s \{task.path} \{unwords task.args}"`

- `Monitor/ProcessStream.idr` lines 96-99: same pattern

- `Worker.idr` line 42: same pattern

---

## Functional Anti-Patterns

### Manual `Maybe` Unwrapping Instead of Monad/Applicative

**File:** `Monitor/Types.idr` lines 152-157

```idris
findSelectedJobName st =
  case indexNat st.selected st.jobs of
    Just e  => if e.status == RUNNING then Just e.task.name else Nothing
    Nothing => Nothing
```

Should be:

```idris
findSelectedJobName st = do
  e <- indexNat st.selected st.jobs
  guard (e.status == RUNNING)
  pure e.task.name
```

**File:** `Monitor/Types.idr` lines 160-164

```idris
findRunningJobName st =
  case find (\e => e.status == RUNNING) st.jobs of
    Just e  => Just e.task.name
    Nothing => Nothing
```

This is literally `map (.task.name) $ find (\e => e.status == RUNNING) st.jobs`.

**File:** `Monitor/Types.idr` lines 119-132 (`updateJobStatus`)

Deeply nested `case` pyramid. Should use `Maybe` monad with `fromMaybe st`:

```idris
updateJobStatus name status st =
  let failed = isFailingStatus status
   in fromMaybe st $ do
        idx <- findEntryIdx name st.jobs
        entry <- indexNat idx st.jobs
        guard (entry.status /= CANCELLED)
        pure $ { jobs := updateAtIdx idx ({ status := status }) st.jobs
               , hasFailed := st.hasFailed || failed
               } st
```

### `concat $ map` Instead of `concatMap`

**File:** `Monitor/ProcessStream.idr` line 98

```idris
concat $ map (\(k,v) => k ++ "=" ++ v ++ " ") task.envVars
```

-> `concatMap (\(k,v) => "\{k}=\{v} ") task.envVars`

### Repeated `View` Painting Pattern

**File:** `Monitor/View.idr` lines 14-37

Six identical `do` blocks for `JobDisplayStatus` painting. Extract a table:

```idris
paint _ window status = do
  let (color, symbol) = statusInfo status
  sgr [SetForeground color]
  showTextAt window.nw symbol
  sgr [Reset]
where
  statusInfo : JobDisplayStatus -> (Color, String)
  statusInfo QUEUED    = (Yellow, "\x23F3")
  statusInfo RUNNING   = (Cyan, "\x23F5")
  ...
```

---

## Opportunities for Better Abstractions

### GADTs: Already Used Well, Could Be Extended

`Protocol.idr` already has excellent GADTs:
- `Ticket : TaskState -> Nat -> Type`
- `StepResult : Nat -> Type`

However, `TaskState` and `JobDisplayStatus` are separate plain enums with a
manual mapping (`toDisplayStatus`). Consider a single indexed type:

```idris
data TaskStatus : Bool -> Type where
  Ready       : TaskStatus False
  InProgress  : TaskStatus False
  Done        : TaskStatus True
  Failed      : TaskStatus True
  TimedOut    : TaskStatus True
  Cancelled   : TaskStatus True
```

The boolean index distinguishes terminal vs non-terminal states, eliminating
the need for runtime checks like
`status == FAILED || status == TIMEDOUT || status == CANCELLED`.

### Applicative/Monad: `MaybeT IO` for `spawnCmd`

**File:** `Monitor/Process.idr` (lines 123-171)

`spawnCmd` has the classic "pyramid of doom" with nested
`if rc < 0 then ... else ...`. Every failure path returns `Nothing`. This is a
perfect fit for `MaybeT IO`:

```idris
spawnCmd : ProcessTask -> IO (Maybe ProcInfo)
spawnCmd task = runMaybeT $ do
  pipeArr <- liftIO $ malloc Fd 2
  rc <- liftIO $ primIO $ prim__pipe (unsafeUnwrap pipeArr)
  guard (rc >= 0)
  buf <- MaybeT $ newBuffer 8
  -- ... etc
```

This flattens the nesting and makes the success path linear.

### `Traversable` / `Foldable` Opportunities

**File:** `Monitor/Types.idr` lines 92-95

`updateAtIdx` is a hand-rolled list traversal. `base` has `replaceAt` in
`Data.Vect` but not `Data.List`. However, `zipWithIndex` + `map` could replace
it, or you could use `Data.List.Elem` for type-safe indexing. Since this is a
UI state update, efficiency is not critical.

---

## Magic Numbers / Unsafe Constants

**File:** `Monitor/Process.idr`
- Line 99: `1025` = `O_WRONLY | O_APPEND`. Should be named.
- Line 111: `544` = unclear open flags. Should be named.
- Line 169: `3` = `F_GETFL`
- Line 170: `4` = `F_SETFL`, `2048` = `O_NONBLOCK`

**File:** `Monitor/ProcessStream.idr`
- Line 101: `524288` = `O_CLOEXEC` = `0x80000`
- Line 142: `1089` = `O_WRONLY | O_CREAT | O_APPEND`, `384` = `0o600` (file mode)

These should be `%foreign` C constants or local `const` definitions. The current
approach is unmaintainable and system-dependent.

---

## Dead Code

- `Monitor/Process.idr` line 242-244: `stripAnsi` is defined but never called
  (only `truncateAnsi` is used in `View.idr`).
- `PipeLeak.idr` lines 136-140: `showChildren` is defined but never called.

---

## Naming Inconsistencies

- `MKProcessTask` (all caps) vs `MkLogLine`, `MkJobEntry`, `MkJobMonitorState`
  (camelCase). Should be `MkProcessTask`.

---

## Minor: Non-English Comments

**Files:** `Worker.idr`, `Main.idr`

Comments like `-- \u0412\u0441\u043F\u043E\u043C\u043E\u0433\u0430\u0442\u0435\u043B\u044C\u043D\u0430\u044F \u0444\u0443\u043D\u043A\u0446\u0438\u044F \u0437\u0430\u043F\u0438\u0441\u0438 \u043B\u043E\u0433\u0430`,
`-- \u0420\u0435\u043A\u0443\u0440\u0441\u0438\u0432\u043D\u043E\u0435 \u0447\u0442\u0435\u043D\u0438\u0435 \u0432\u0441\u0435\u0445 \u0441\u0442\u0440\u043E\u043A` are in Russian. The rest of the
codebase and all identifiers are English. Inconsistent.

---

## Summary Table

| Issue | Severity | Files |
|-------|----------|-------|
| Process spawn duplication | Critical | Process.idr, ProcessStream.idr, PipeLeak.idr |
| `loadTasks` duplication | Critical | Main.idr, Provider.idr |
| Magic numbers | High | Process.idr, ProcessStream.idr |
| Missing documentation | High | All |
| `mutual` blocks | Medium | Process.idr |
| String `++` instead of interpolation | Medium | Process.idr, ProcessStream.idr, Worker.idr |
| Manual `Maybe` unwrapping | Medium | Types.idr |
| `primIO`/`ignore` misuse | Medium | Process.idr |
| `concat $ map` anti-pattern | Low | ProcessStream.idr |
| Dead code | Low | Process.idr, PipeLeak.idr |
| Naming inconsistency | Low | Protocol.idr |

---

## Recommendations

1. **Start with deduplicating the process spawning code.** This is the
   highest-impact change and eliminates a class of bugs where fixes in one copy
   are forgotten in the others.

2. **Replace magic numbers with named constants.** This is a prerequisite for
   maintaining the FFI code safely.

3. **Flatten the `Maybe` pyramids in `Monitor.Types.idr`.** This makes the state
   update functions significantly more readable and less error-prone.

4. **Eliminate `mutual` blocks** in `Monitor/Process.idr` by using forward
   declarations.

5. **Add documentation** to all exported definitions. This is the most important
   rule per STYLE.md.

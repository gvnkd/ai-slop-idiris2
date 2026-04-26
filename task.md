# Migrate Process Output Handling to streams Library

## Overview

Replace the current polling-based process output handling with the `streams` library
(`idris2-streams` by Stefan Hoelck). The current approach in `Monitor/Source.idr` uses a
100ms-sleep polling loop with `readres` to read from pipe FDs. The streams library provides
a more efficient event-driven architecture built on `IO.Async`.

**Goal:** Each spawned process produces an `AsyncStream` of its output. The streams from all
active processes are merged via `FS.Concurrent.merge` (or managed manually). Output is
streamed to the TUI event queue and optionally to log files, using streams combinators
(`foreach`, `observe`, `lines`, `UTF8.decode`, etc.).

## Current Architecture

```
spawnCmd → ProcInfo {fd, pid, pending, logPath}
              ↓
resultsSource (EventSource)
  └─ loop: sleep 100ms → pollAll → pollOne per ProcInfo
      └─ readres fd String 4096
          ├─ NoData  → waitpid WNOHANG (still alive? → keep)
          ├─ EOI     → waitpid, close fd, emit JobFinished, writeLogFooter
          ├─ Closed  → close fd, emit JobFinished FAILED, writeLogFooter
          ├─ Interrupted → keep
          └─ Res chunk → stripAnsi → splitOutput → emit JobOutput
```

**Problems with current approach:**
- Busy-polling with 100ms sleep (latency, wasted CPU)
- Manual FD management (open, close, non-blocking setup)
- String-based reads with manual line splitting (`splitOutput`)
- ANSI stripping done manually character-by-character (`stripAnsi`)
- Log file I/O done manually with raw `open`/`write`/`close`
- `weakenErrors` scattered throughout to work around error type issues
- `try [onErrno]` + `weakenErrors` pattern is fragile

## Target Architecture

```
spawnProcess → Pull that produces ByteString chunks from child stdout/stderr
              ↓
  FS.Bytes.UTF8.decode  → String chunks
              ↓
  FS.Bytes.lines        → List ByteString (line-broken)
              ↓
  observe / foreach     → emit TUI events + write to log file
              ↓
  On stream end (Left result) → emit JobFinished, writeLogFooter
```

## Key streams Concepts

- `Pull f o es r` — effectful computation producing output chunks of type `o`,
  errors from `HSum es`, final result `r`
- `Stream f es o` = `Pull f o es ()` — stream with no final result
- `AsyncStream e es o` = `Stream (Async e) es o` — async stream
- `exec` — lift an effect into a Pull
- `emit` — emit a chunk of output
- `uncons` — unwrap one chunk (the primitive for iteration)
- `pull` — run a Pull to completion, returning `Outcome es r`
- `foreach` — drain a stream, running an action per chunk
- `observe` — run an action per chunk without consuming output
- `newScope` / `acquire` — resource management (auto-cleanup on scope exit)
- `FS.Concurrent.merge` — merge multiple streams nondeterministically
- `FS.Concurrent.timeout` — interrupt a stream after a duration
- `FS.Posix.bytes fd n` — stream ByteStrings from an FD using `readnb`
- `FS.Bytes.lines` — break ByteString stream into `(List ByteString)` lines
- `FS.Bytes.UTF8.decode` — ByteString → String conversion

## Integration Challenge: EventSource vs. AsyncStream

The TUI framework expects `EventSource evts` which is `EventQueue evts -> NoExcept ()`.
`NoExcept` is `Async Poll [] a` (infallible async). The streams library operates in
`Async e es a` (with error types).

**Bridge approach:** Run a streams `Pull` inside an `EventSource` by calling `pull` and
handling the `Outcome`. Since `EventSource` is a long-running loop, we wrap the stream
processing in a loop that handles process lifecycle (spawn → stream → finish → next queued).

Alternatively, convert each process stream into a producer that writes to the event queue,
running the pull in the background via `parrun`.

**Chosen approach:** Keep the `EventSource` pattern but replace the polling loop with a
streams-based loop. The `resultsSource` function will:
1. Build a `Pull` per active process (spawn → stream bytes → decode → lines → events)
2. Merge all process pulls using `merge` (or run them as parallel fibers writing to the queue)
3. Handle queued task spawning when slots free up

## Files to Modify

| File | Changes |
|------|---------|
| `amon.ipkg` | Add `streams`, `streams-posix` dependencies |
| `src/Monitor/Process.idr` | Major rewrite: replace manual pipe/FD management with streams-based process spawning; replace `stripAnsi`, `splitOutput` with streams combinators; replace log I/O with `FS.Posix` writers |
| `src/Monitor/Source.idr` | Major rewrite: replace polling loop with streams-based event source |
| `src/Monitor/Main.idr` | Minor: adjust types if `ProcInfo` changes |
| `src/Monitor/Types.idr` | Likely no changes |
| `src/cstr_write.c` | May be eliminated (streams handles file I/O) |

## Step-by-Step Plan

### Phase 1: Dependencies and Skeleton

#### Step 1.1: Add streams dependencies to amon.ipkg
Add `streams` and `streams-posix` to the `depends` line in `amon.ipkg`. Verify the
package names match what the flake builds (`streams` and `streams-posix`).

```
depends = base >= 0.5.1, contrib, linear, json, elab-util, ansi, tui, tui-async, posix, streams, streams-posix
```

**Potential issue:** The streams package may need additional transitive dependencies
(`hashable`, `containers`, `bytestring`, `elin`, etc.) that are not currently in
`amon.ipkg`. The flake builds these, but `.ipkg` only lists direct dependencies.
We may need to add them. Check at compile time.

**Test:** `idris2 --build amon.ipkg` should succeed (even if modules don't compile yet).

---

#### Step 1.2: Create new `Monitor/ProcessStream.idr` module
Create a new module to house the streams-based process handling, keeping the old
`Monitor/Process.idr` for reference during migration.

New module will contain:
- `ProcessPull` type: a `Pull (Async Poll) ByteString [Errno] (Int, String?)` — reads from
  child process, returns `(exitCode, maybeLogPath)` on completion
- `spawnProcess : ProcessTask -> Pull (Async Poll) ByteString [Errno] (Int, Maybe String)`
  — spawns child, creates pipe, streams output via `FS.Posix.bytes`, returns exit code
- Log file integration using `observe` + `FS.Posix.appendFile`
- Line breaking using `FS.Bytes.lines` and `FS.Bytes.UTF8.decode`

**Test:** Can import the module without errors.

---

#### Step 1.3: Implement `spawnProcess` — child process spawning with pipe streaming
This is the core of the migration. The function will:

1. Build shell command (timeout + path + args, optionally wrapped with tee for logging)
2. Create pipe via C FFI (`pipe`)
3. Fork child process
4. In child: dup2, execvp (same as current `spawnCmd`)
5. In parent: use `FS.Posix.bytes readFd bufSize` to create a `ByteString` stream from
   the read end of the pipe
6. Wrap the stream with resource cleanup (`acquire`/`bracket`) to close the FD on exit
7. On stream completion (EOF), call `waitpid` to get exit code
8. Return result as `Pull` result

Key challenge: `FS.Posix.bytes` reads until EOF, but we need to know the exit code.
The approach: after the byte stream ends (EOF on pipe), run `waitpid` as a final action
in the Pull, returning the exit code.

**Signature:**
```idris
spawnProcess : ProcessTask -> Pull (Async Poll) ByteString [Errno] (Int, Maybe String)
spawnProcess task =
  -- 1. Acquire pipe FDs
  -- 2. Fork + exec
  -- 3. Stream bytes from read end
  -- 4. On EOF: waitpid, close FD, return (exitCode, logPath)
  ```

**Potential issues:**
- `FS.Posix.bytes` uses `readnb` internally, which requires `PollH` evidence. We need
  `{auto pol : PollH Poll}` in scope. This should be available from the epoll loop.
- The `FS.Posix.bytes` function has implicit constraints: `{auto has : Has Errno es}`.
  Our error type is `[Errno]`, so `Has Errno [Errno]` should be satisfied.
- The `bytes` function signature: `bytes : FileDesc a => a -> Bits32 -> AsyncStream e es ByteString`
  This returns an `AsyncStream`, which is `Stream (Async e) es ByteString`. We need to
  lift this into a `Pull` context. Use `exec` to lift each `Async` action, or use the
  stream directly within a larger `Pull`.

**Actual approach:** Since `spawnProcess` returns a `Pull (Async Poll) ...`, and
`FS.Posix.bytes` returns `AsyncStream (Async Poll) [Errno] ByteString`, these are
compatible. We can use the stream directly within a `do` block in the Pull context:

```idris
spawnProcess task = do
  -- setup pipe, fork, exec
  -- Then stream output:
  bsStream @{...} = bytes readFd 4096  -- this is an AsyncStream
  -- We need to "run" this stream as part of our Pull
  -- After stream ends, waitpid and return result
```

**Workaround:** The `bytes` stream lives in `Async e` monad, not `Pull (Async e)`.
We need to bridge. The streams library provides `pull : Pull f Void es r -> f [] (Outcome es r)`,
which runs a pull to completion. But we want the opposite — embed an `AsyncStream` into
a `Pull`. We can do this by converting the `AsyncStream` into a Pull via `unfoldEvalMaybe`:

```idras
streamToPull : AsyncStream e es o -> Stream (Async e) es o
streamToPull = id  -- they're the same type!
```

Actually, `AsyncStream e es o` IS `Stream (Async e) es o` which IS `Pull (Async e) o es ()`.
So they are the same type. We can sequence them directly.

**Revised approach for spawnProcess:**
```idris
spawnProcess : ProcessTask -> Pull (Async Poll) ByteString [Errno] (Int, Maybe String)
spawnProcess task = do
  -- Setup: acquire pipe, fork, exec (using exec/liftIO)
  -- ...
  -- Stream output (this IS a Pull (Async Poll) ByteString [Errno] ()):
  bytes readFd 4096  -- emits ByteStrings until EOF
  -- After stream ends:
  -- waitpid and return result
  pure (exitCode, logPath)
```

Wait — `bytes` returns `AsyncStream`, which is `Stream (Async e) es ByteString`.
But our function returns `Pull (Async Poll) ByteString [Errno] R`. These are compatible
since `Stream (Async e) es o` = `Pull (Async e) o es ()`.

So the flow is:
```
bytes readFd 4096  -- Pull (Async Poll) ByteString [Errno] ()
  >>               -- monadic bind: after stream ends,
  waitpidAndReturn  -- Pull (Async Poll) ByteString [Errno] (Int, Maybe String)
```

This should work!

**Test:** Type-checks, compiles.

---

#### Step 1.4: Add log file integration with streams
Instead of the current `tee`-based approach and manual `openLogFile`/`writeLogFooter`,
use streams combinators:

```idris
-- Observe output and write to log file:
observe (writeToLogFile logPath) (bytes readFd 4096)
```

Where `writeToLogFile` opens the file, writes the `[START]` header, and appends each chunk.
Use `FS.Posix.appendFile` or raw FD writes via `FS.Posix.writeTo`.

For the header/footer:
```idris
spawnProcess task = do
  -- Write [START] header:
  exec $ writeLogHeader logPath  -- using existing C FFI or FS.Posix
  
  -- Stream with logging side-channel:
  observe (writeToFd logFd) $ bytes readFd 4096
  
  -- Get exit code:
  exitCode <- waitpid pid
  
  -- Write [END] footer:
  exec $ writeLogFooter logPath exitCode
  
  pure (exitCode, logPath)
```

**Potential issue:** The `observe` combinator runs in the Pull context. The `writeToFd`
action needs to be in `Async Poll`. Use `fwritenb` from `IO.Async.Posix` or lift raw
`primIO` writes.

**Simpler approach:** Keep using the `cstr_write` C FFI for log writes, but wrap in
`liftIO` within the Pull context. Or better, use `FS.Posix.writeTo fd` which is already
a streams combinator.

**Test:** Log file gets written with [START]/[END] markers.

---

#### Step 1.5: Add line-breaking and UTF-8 decoding
Replace the current `splitOutput` and manual String handling:

```idris
-- Current: readres → String → stripAnsi → splitOutput → List String
-- New: bytes → UTF8.decode → lines → List ByteString → events
```

Pipeline:
```idris
bytes readFd 4096
  >>= \_ => -- need to compose as a Pull, not monadic bind on result
```

Actually, the pipeline chains naturally in a Pull:
```idris
-- This emits ByteString chunks:
bytes readFd 4096

-- To break into lines and decode, we need to transform the output type.
-- Use mapOutput for UTF8 decode, then lines for line-breaking.
```

Wait — `FS.Bytes.UTF8.decode` converts `Stream f es ByteString` → `Stream f es String`.
And `FS.Bytes.lines` converts `Pull f ByteString es r` → `Pull f (List ByteString) es r`.

We want to:
1. Read raw bytes: `bytes readFd 4096` → emits `ByteString`
2. Break into lines: `lines` → emits `(List ByteString)`
3. Convert to strings for TUI events

But we also need to handle ANSI stripping. The current `stripAnsi` is complex
(cursor position tracking). With streams, we could:
- Keep `stripAnsi` as-is and apply it per-chunk with `mapOutput`
- Or express it as a stream combator (more complex, but cleaner)

**Decision for now:** Keep `stripAnsi` as a function, apply with `P.mapOutput` or
`C.mapOutput` on each chunk. Later, refactor into a proper stream combinator.

**Revised pipeline:**
```idris
bytes readFd 4096
  -- Now we have a Stream of ByteStrings
  -- Apply UTF8 decode to get Strings, then process lines
```

Actually, let's think about the order:
1. `bytes` → `ByteString` chunks (raw output from pipe)
2. These need to go to: (a) log file (raw), (b) TUI (decoded + line-broken)
3. For logging: just write raw bytes (or raw strings)
4. For TUI: decode UTF-8 → break into lines → strip ANSI → emit events

For (a) and (b) simultaneously, use `observe` for logging:
```idris
observe (writeToLog logFd) $
  bytes readFd 4096
```

Then for TUI processing, we need a separate pass. But `observe` doesn't consume the
stream — it tees the side effect. So:

```idris
-- In the Pull:
observe (writeToLog logFd) $ bytes readFd 4096
-- At this point, the bytes have been emitted AND written to log.
-- But we also need to process them for TUI events...
```

**Problem:** After `observe`, the stream has been consumed (in the Pull, sequencing
means the output passes through). But we need BOTH logging AND event emission.

**Solution:** Use `observe` for the log side-effect, and the emitted output is still
available downstream for TUI processing. The `observe` combinator runs the side effect
AND passes the value through:

```idris
observe : (o -> f es ()) -> Pull f o es r -> Pull f o es r
```

So `observe` writes to log AND passes through the ByteString. Then we can chain
line-breaking and event emission.

But the TUI event emission also needs to happen for each chunk. This is another
side-effect. We can chain two `observe`s, or use a single `observe` that does both:

```idris
observe (\chunk => do
  writeToLog logFd chunk      -- side effect 1: write to file
  emitTUIEvents chunk queue   -- side effect 2: emit to event queue
) $ bytes readFd 4096
```

However, the TUI events need line-broken, ANSI-stripped strings. So we need to
transform the stream first, then observe. But the log should get raw output.

**Revised approach:**
```idris
-- First observe for raw logging:
observe (writeToLog logFd) $
  -- Then transform for TUI:
  UTF8.decode $              -- ByteString → String
    bytes readFd 4096

-- Then observe transformed output for TUI events:
-- But wait, observe is on the outside now...
```

Let me think about this more carefully with the Pull structure:

```idris
-- The full Pull for one process:
spawnProcess task = do
  -- Setup: pipe, fork, exec
  logFd <- maybeOpenLog task.logFile
  case logFd of
    Just fd => exec $ writeLogHeader fd  -- [START] timestamp
    Nothing => pure ()

  -- Stream pipeline:
  -- 1. Read bytes from pipe
  -- 2. For each ByteString chunk: write to log (if log file set), emit TUI event
  bytes readFd 4096
    -- At this point, ByteString chunks are emitted.
    -- We need to both log them AND emit TUI events.
    -- But we can't "branch" a Pull easily.

  -- Cleanup
  exec $ maybeCloseLog logFd
```

**Actual solution:** The key insight is that in a `Pull`, output values flow through
the pipeline. We use `observe` to add side effects without consuming output, and
`mapOutput`/`P.mapOutput` to transform values. For two independent side effects
(raw log + TUI events), we can use two `observe`s at different stages:

```idris
-- Approach: Process the stream for TUI events, and observe raw output for logging.
-- But TUI processing (line-breaking, ANSI stripping) changes the output type,
-- so we can't do both on the same stream directly.

-- Better approach: In the observe callback, do BOTH things:
observe (\rawChunk => do
  -- Log raw bytes:
  case logFd of
    Just fd => fwritenb fd rawChunk
    Nothing => pure ()
  -- Process for TUI: decode, strip ANSI, break into lines, emit events
  let decoded = UTF8.toString rawChunk  -- or use proper decode
  let clean = stripAnsi decoded
  -- Split into lines and emit...
  -- But this is effectful (needs to write to event queue)
  emitTUIEvents clean queue
) $ bytes readFd 4096
```

This works! The `observe` callback runs in `Async Poll`, and both `fwritenb` and
writing to the event channel are `Async` actions.

**Potential issue:** `emitTUIEvents` needs to write to the event queue, which is a
`Channel`. The `send` function is `Async`. We need `weakenErrors` for the `send`
result (it can fail if the channel is full/closed).

**Test:** The pull type-checks with the observe callback.

---

#### Step 1.6: Handle process completion (waitpid, exit code, log footer)
After the byte stream ends (EOF on pipe), the child process has finished writing.
We need to:
1. Call `waitpid` to get exit code
2. Write log footer with status
3. Emit `JobFinished` event to the queue
4. Close the pipe FD

In the Pull:
```idris
  -- After the stream ends:
  (exitStatus, _) <- exec $ waitpid pid WNOHANG
  exec $ writeLogFooter logFd (fromExitCode exitStatus)
  exec $ emitJobFinished exitStatus queue
  exec $ closeFd readFd
  pure (exitCode, logPath)
```

**Potential issue:** `waitpid` is in `IO`, not `Async`. Need to lift with `exec . liftIO`.

---

### Phase 2: Source.idr — Replace polling loop

#### Step 2.1: Redesign `resultsSource` as streams-based EventSource
The current `resultsSource` is:
```idris
resultsSource : Has JobUpdate evts => List ProcInfo -> List ProcessTask -> EventSource evts
```

The new version will be:
```idris
resultsSource : Has JobUpdate evts => List ProcessTask -> List ProcessTask -> EventSource evts
```

(Takes initial tasks and queued tasks, no longer needs `ProcInfo` since process
state is managed by the Pull itself.)

The EventSource will:
1. Build a list of `ProcessTask` to run
2. For each active task, build a `Pull` that handles the full lifecycle
3. Run all pulls concurrently, writing events to the queue
4. When a task finishes, spawn the next queued task (if any)

**Challenge:** Streams `merge` merges streams that are already defined. But we need
to dynamically spawn new tasks as slots free up. The `parJoin` combinator is designed
for this — it takes an "outer" stream of inner streams, and runs at most N
concurrently.

**Using `parJoin`:**
```idris
parJoin : Nat -> AsyncStream e es (AsyncStream e es o) -> AsyncStream e es o
```

The outer stream emits inner streams (one per task). `parJoin` runs at most N inner
streams concurrently. When one finishes, it pulls the next from the outer stream.

This is perfect for our use case:
```idris
-- Outer stream: emits one process-stream per task
taskStreams : List ProcessTask -> AsyncStream e es (AsyncStream e es JobEvent)
taskStreams tasks = emits (map streamForTask tasks)

-- parJoin maxWorkers taskStreams
-- → merges output from all running tasks, respecting worker limit
```

**However:** `parJoin` expects `AsyncStream`, which is infinite by default. Our
per-process streams are finite (they end when the process exits). This is fine —
`parJoin` handles finite inner streams.

**Another challenge:** `parJoin` returns a merged stream of the inner output type.
We need to emit TUI events as a side effect, not as the stream output. Use `observe`
or `foreach` inside the per-process pull.

**Revised design:**
```idris
streamForTask : Has JobUpdate evts => ProcessTask -> EventQueue evts
               -> AsyncStream e es ()
streamForTask task queue = do
  -- This is a Pull/Stream that:
  -- 1. Spawns the process
  -- 2. Streams output, emitting TUI events via observe
  -- 3. On completion, emits JobFinished
  -- The output type is () since all work is done via side effects (observe)
  ```

Then the outer stream:
```idris
emits (map (\t => streamForTask t queue) tasks)
```

And `parJoin maxWorkers outerStreams` gives us a merged stream.

But wait — `parJoin` merges the OUTPUT of inner streams. Since our inner streams
output `()`, the merged stream also outputs `()`. We use `foreach (const $ pure ())`
or `drain` to consume it.

**Full EventSource:**
```idris
resultsSource : Has JobUpdate evts => List ProcessTask -> List ProcessTask
               -> EventSource evts
resultsSource initial queued queue = do
  let allTasks = initial ++ queued
  let outer = emits (map (\t => processPull t queue) allTasks)
  -- Run with maxWorkers concurrency:
  pull $ drain $ parJoin maxWorkers outer
  -- The drain consumes all output; events are emitted via observe in processPull
```

Wait — `pull` runs in `Async e`, not in `NoExcept`. We need to bridge.

**Bridge:** `pull` returns `Async Poll [] (Outcome [Errno] R)`. We're in `NoExcept`
which is `Async Poll [] ()`. So we can call `pull` with `exec` or just directly.

Actually, `NoExcept a` = `Async Poll [] a`. And `pull` returns `f [] (Outcome es r)`
where `f = Async Poll`. So `pull` returns `Async Poll [] (Outcome [Errno] R)`.
We can call this directly in our `NoExcept` context, then handle the `Outcome`.

```idris
resultsSource initial queued queue = do
  let allTasks = initial ++ queued
  let outer = emits (map (\t => processPull t queue) allTasks)
  outcome <- pull $ drain $ parJoin maxWorkers outer
  case outcome of
    Succeeded _ => pure ()
    Canceled    => pure ()
    Error err   => logError err
```

**Problem:** `parJoin` requires `IsSucc maxWorkers` (must be > 0). We can hardcode
or pass it.

**Problem:** `parJoin` takes `AsyncStream e es (AsyncStream e es o)`. Our inner
streams have type `AsyncStream Poll [Errno] ()`. The outer emits these.
The merged stream is `AsyncStream Poll [Errno] ()`.

Actually wait, `parJoin maxOpen outer` where outer is
`AsyncStream e es (AsyncStream e es o)`. The inner streams are
`AsyncStream e es o`. So if inner streams are `AsyncStream Poll [Errno] ()`,
then outer is `AsyncStream Poll [Errno] (AsyncStream Poll [Errno] ())`.

Then `emits (...)` gives us that if we map `processPull` over tasks.

But `emits` has type `List o -> Stream f es o`. Here `o = AsyncStream Poll [Errno] ()`.
So `emits (map processPull allTasks)` has type `Stream (Async Poll) [Errno] (AsyncStream Poll [Errno] ())`.

Which is `AsyncStream Poll [Errno] (AsyncStream Poll [Errno] ())`.

Then `parJoin maxWorkers` gives `AsyncStream Poll [Errno] ()`.

And `drain` gives `Pull (Async Poll) Void [Errno] ()`.

And `pull` gives `Async Poll [] (Outcome [Errno] ())`.

Wait, `pull : Pull f Void es r -> f [] (Outcome es r)`. The `f []` means no errors.
So `pull` catches errors and returns them in the `Outcome`.

This all type-checks!

**But:** There's a subtle issue. `parJoin` expects the inner streams to produce
output that gets merged. If inner streams produce `()`, the merged output is `()`.
We'd need to `drain` the result. But the point of using `observe` inside each
inner stream is that the actual work (event emission) happens as a side effect
of streaming, not from the output values.

So the flow is:
1. `parJoin` runs inner streams concurrently
2. Each inner stream (`processPull`) reads process output via `bytes`, and uses
   `observe` to emit TUI events
3. Inner streams complete when the process exits
4. `parJoin` emits `()` for each inner stream completion
5. We `drain` and `pull` the result

This works, but we lose the ability to react to individual process completion
(for spawning queued tasks). With `parJoin`, the concurrency is managed
automatically — when one inner stream finishes, `parJoin` starts the next
from the outer stream.

**This is actually perfect!** `parJoin` handles the worker pool automatically:
- Outer stream emits inner streams (one per task)
- `parJoin N` runs at most N inner streams concurrently
- When one finishes, it pulls the next from the outer stream
- No manual queue management needed!

**Revised EventSource:**
```idris
resultsSource : Has JobUpdate evts => List ProcessTask -> EventSource evts
resultsSource allTasks queue = do
  let outer : AsyncStream Poll [Errno] (AsyncStream Poll [Errno] ())
      outer = emits (map (\t => processPull t queue) allTasks)
  outcome <- pull $ drain $ parJoin maxWorkers outer
  case outcome of
    Succeeded _ => pure ()
    Canceled    => pure ()
    Error err   => pure ()  -- log error
```

This replaces the entire polling loop with a single `pull` call!

---

#### Step 2.2: Implement `processPull` — per-process lifecycle as a Pull
```idris
processPull : Has JobUpdate evts => ProcessTask -> EventQueue evts
            -> AsyncStream Poll [Errno] ()
processPull task queue = do
  -- 1. Spawn process, get pipe FD and PID
  (readFd, pid, logFd) <- exec $ liftIO $ setupProcess task

  -- 2. Acquire resources (will be cleaned up on scope exit):
  acquire (pure readFd) (\fd => liftIO $ prim__close fd)
  -- Similarly for logFd

  -- 3. Write log header:
  case logFd of
    Just fd => exec $ liftIO $ writeLogHeader fd
    Nothing => pure ()

  -- 4. Stream output with logging + TUI events:
  observe (\rawChunk => do
    -- Log raw output:
    case logFd of
      Just fd => fwritenb fd rawChunk
      Nothing => pure ()
    -- Process for TUI:
    let decoded = decodeUTF8Chunk rawChunk
    let clean = stripAnsi decoded
    emitLinesForTask task clean queue
  ) $ bytes readFd 4096

  -- 5. Wait for exit:
  exitCode <- exec $ liftIO $ waitpidExitCode pid

  -- 6. Write log footer:
  case logFd of
    Just fd => exec $ liftIO $ writeLogFooter fd exitCode
    Nothing => pure ()

  -- 7. Emit JobFinished event:
  exec $ liftIO $ emitJobFinished task exitCode queue
```

**Potential issues with this approach:**
- `bytes` is an `AsyncStream`, not a `Pull` we can insert in a `do` block
- Need to properly sequence: setup → stream → cleanup

Actually, since `AsyncStream` = `Stream (Async e)` = `Pull (Async e) o es ()`,
it IS a Pull. We can sequence it in a `do` block within a larger Pull.

But the `observe` callback needs to access `logFd` and `queue`, which are
local variables. This is fine — they're captured in the lambda.

**Key challenge:** The `observe` callback runs in `Async Poll`, but writing to
the event queue is also async. We need to make sure the callback is total
and handles errors (channel might be closed).

**Line breaking in the observe callback:**
The `bytes` stream emits arbitrary ByteString chunks. We need to break them
into lines for TUI events. Doing this correctly across chunk boundaries
requires state (pending partial line). Options:
1. Use `FS.Bytes.lines` as a stream combinator, then observe the line lists
2. Maintain pending state manually in the observe callback

Option 1 is cleaner. The pipeline becomes:
```idris
  lines $ UTF8.decode $ bytes readFd 4096
```
This gives us `Pull (Async Poll) (List String) [Errno] ()` (after UTF8 decode
gives String, lines breaks into List).

Wait — `UTF8.decode` is `Stream f es ByteString -> Stream f es String`.
And `lines` is `Pull f ByteString es r -> Pull f (List ByteString) es r`.

So the order matters:
- `bytes` → `ByteString` chunks
- `lines` needs `ByteString` input → breaks into `(List ByteString)`
- `UTF8.decode` converts `ByteString` → `String`

If we apply `lines` first: `lines $ bytes readFd 4096` → emits `(List ByteString)`
(each list is lines from one chunk, broken on `\n`).

Then `P.mapOutput` to convert each `ByteString` in the list to `String`.

**Actually:** Let's use `FS.Bytes.lines` on the raw bytes, then map each line
through UTF8 decode and ANSI stripping in the observe callback.

```idris
  observe (\lineList => do
    -- lineList : List ByteString (lines from this chunk)
    for_ lineList $ \line => do
      -- Log raw:
      case logFd of Just fd => fwritenb fd line, Nothing => pure ()
      -- TUI:
      let str = UTF8.toString line
      let clean = stripAnsi str
      emitLine task clean queue
  ) $ lines $ bytes readFd 4096
```

Hmm, but `observe` gets `(List ByteString)` per chunk, not individual lines.
And `emitLine` needs to handle partial lines (a line might span chunks).
The `lines` combinator handles this by maintaining internal state.

Wait — `FS.Bytes.lines` emits `(List ByteString)` per input chunk, where each
element is a complete line (broken on `\n`). The last element might be a
partial line. Let me check the implementation.

From `FS.Bytes.lines`:
```idris
lines : Pull f ByteString es r -> Pull f (List ByteString) es r
lines = scanFull empty splitNL (map pure . nonEmpty)
```

This uses `scanFull` which maintains state across chunks. The output is
`(List ByteString)` where each ByteString is a complete line (without the
newline character). The final `scanFull` also emits any remaining partial
line via the `last` function.

So yes, each element of the emitted list is a complete line. We can process
them individually.

**Refined processPull:**
```idris
processPull task queue = do
  -- Setup (in IO, lifted to Pull):
  (readFd, pid, logFd) <- exec $ liftIO $ setupProcess task

  acquire (pure readFd) (\fd => liftIO $ prim__close fd)
  case logFd of
    Just fd => acquire (pure fd) (\fd => liftIO $ prim__close fd)
    Nothing => pure ()

  case logFd of
    Just fd => exec $ liftIO $ writeLogHeader fd
    Nothing => pure ()

  -- Stream pipeline: raw bytes → lines → observe (log + TUI events)
  observe (\lineList => for_ lineList $ \line => do
    -- Log raw bytes:
    case logFd of
      Just fd => fwritenb fd line
      Nothing => pure ()
    -- TUI event:
    let str = decodeUTF8 line
    let clean = stripAnsi str
    weakenErrors $ emitLine task clean queue
  ) $ lines $ bytes readFd 4096

  -- Cleanup:
  (_, status) <- exec $ liftIO $ waitpid pid WNOHANG
  let exitCode = fromStatus status
  case logFd of
    Just fd => exec $ liftIO $ writeLogFooter fd exitCode
    Nothing => pure ()
  weakenErrors $ emitJobFinished task exitCode queue
```

**Test:** This type-checks and the types flow correctly.

---

#### Step 2.3: Update `Monitor/Main.idr`
The main function needs to:
1. Create all `ProcessTask` entries from `tasks.json`
2. Pass them to `resultsSource`
3. The `EventSource` runs the entire pipeline

```idris
run : IO ()
run = do
  ignore $ system "mkdir -p logs"
  Just tasks <- loadTasks "tasks.json"
    | Nothing => die "Failed to load tasks.json"
  let entries = toJobEntries tasks
  let initState = initialState entries
  let mainLoop = asyncMain {evts = [JobUpdate, Key]} [resultsSource tasks]
  Prelude.ignore $ runView mainLoop handler initState
```

Note: `resultsSource` now takes `List ProcessTask` instead of
`(List ProcInfo, List ProcessTask)`. The initial/queued split is handled
by `parJoin` internally.

---

#### Step 2.4: Remove `ProcInfo` and related code
Once the migration is complete, remove:
- `ProcInfo` record from `Monitor/Process.idr`
- `spawnCmd` from `Monitor/Process.idr`
- `splitOutput`, `stripAnsi` helper functions (or keep `stripAnsi` if still needed)
- `openLogFile`, `writeLogChunk`, `writeLogFooter` (replace with streams equivalents)

Keep:
- C FFI declarations (pipe, fork, execvp, etc.) — still needed for spawning
- `stripAnsi` — still needed for ANSI processing (unless we refactor it into
  a stream combinator later)

---

### Phase 3: Logging with streams

#### Step 3.1: Replace manual log I/O
Current approach:
- `openLogFile` opens file, writes `[START]` header, returns `Maybe Int` (FD)
- `writeLogChunk` writes chunk to FD
- `writeLogFooter` appends `[END]` footer

New approach using streams:
- Use `FS.Posix.writeFile` or `FS.Posix.appendFile` for the log
- Or keep raw FD writes but use `acquire` for automatic cleanup

**Decision:** Keep raw FD writes for performance (avoiding allocations in the
hot path), but use `acquire` for automatic cleanup:

```idris
acquire (openLogFile path) (\fd => prim__close fd)
```

The `[START]` header is written in the `acquire` action. The `[END]` footer
is written after the stream completes.

**Alternative:** Use `FS.Posix.appendFile path pull` which handles opening,
writing, and closing automatically. But this creates a new Pull for the file
write that runs in parallel with the main stream.

**Decision for now:** Keep manual FD management within `acquire` for simplicity
and control.

---

#### Step 3.2: Handle `tee`-based logging elimination
The current approach wraps the command with `tee -a logfile` in the shell.
With streams, we handle logging in Idris code, so the shell wrapper is no
longer needed. The command simplifies to:

```idris
let cmd = "timeout " ++ show task.timeout ++ "s " ++ task.path ++ " " ++ unwords task.args
```

No more `tee`, no more `[START]` header injection in the shell command.

---

### Phase 4: C FFI and cstr_write.c

#### Step 4.1: Assess cstr_write.c usage
Current usage:
- `cstr_write` — write string to FD (used for log writes)
- `cstr_timestamp` — formatted timestamp (used for log headers/footers)

With streams migration:
- `cstr_write` can be replaced by `fwritenb` from `IO.Async.Posix`
- `cstr_timestamp` can be replaced by Idris code using `IO.Async` time functions

**Decision:** Keep `cstr_write.c` for now (it works, and `fwritenb` may not
support arbitrary FDs). Replace `cstr_timestamp` with native Idris time
formatting if available.

**Alternative:** Use `FS.Posix.writeTo fd pull` for log writes, which uses
the streams library's own write infrastructure.

---

### Phase 5: Testing and Validation

#### Step 5.1: Compile and run basic test
After implementing the migration:
1. `idris2 --build amon.ipkg` — must compile
2. `./build/exec/amon` — must run and show TUI
3. Verify tasks execute, output appears in TUI
4. Verify log files are created with correct format

#### Step 5.2: Test edge cases
- Process that exits immediately
- Process with large output
- Process with ANSI escape sequences
- Process with partial lines (no trailing newline)
- Process that fails (non-zero exit code)
- Multiple concurrent processes
- Queued tasks that start after initial batch completes

#### Step 5.3: Performance comparison
Compare with the old polling approach:
- Latency: output should appear in TUI faster (no 100ms polling delay)
- CPU usage: should be lower (event-driven vs. polling)

## Potential Issues and Workarounds

### Issue 1: `PollH Poll` constraint
`FS.Posix.bytes` requires `{auto pol : PollH Poll}`. The `Poll` type is from
`IO.Async.Loop.Poller`. The constraint is available when running under the
epoll event loop. Make sure the implicit is in scope.

**Workaround:** If the constraint cannot be resolved automatically, pass it
explicitly with ` @{...}` syntax.

### Issue 2: `parJoin` requires `IsSucc maxWorkers`
`parJoin` requires proof that `maxWorkers > 0`. Use a literal like `3`
or construct the proof explicitly.

**Workaround:** `parJoin (S Z) ...` or `parJoin {prf = ?} 3 ...`

### Issue 3: Error types in `observe` callback
The `observe` callback runs in `f es`, meaning it can produce errors. If the
callback throws an error, the entire Pull fails. We need to handle errors
gracefully (log and continue, not abort).

**Workaround:** Use `try` inside the callback, or use `handle` to catch errors.
Or use `weakenErrors` / `unerr` to convert fallible actions to infallible ones.

### Issue 4: `EventSource` expects `NoExcept`, streams produce errors
`EventSource evts = EventQueue evts -> NoExcept ()` where `NoExcept = Async Poll []`.
But streams operations can fail with `[Errno]`. The `pull` function returns
`Outcome [Errno] r`, which we need to handle.

**Workaround:** Handle the `Outcome` in the `EventSource`:
```idris
case outcome of
  Succeeded _ => pure ()
  Canceled    => pure ()
  Error err   => weakenErrors $ logError err
```

### Issue 5: `stripAnsi` operates on `String`, but streams give `ByteString`
Need to convert `ByteString` → `String` before ANSI stripping.

**Workaround:** Use `UTF8.decode` before `stripAnsi`, or convert in the
`observe` callback.

### Issue 6: Line boundaries across chunks
The `FS.Bytes.lines` combinator handles this correctly by maintaining
internal state. No workaround needed.

### Issue 7: Dynamic task spawning
`parJoin` handles this automatically — when an inner stream finishes, it
pulls the next from the outer stream. No manual queue management needed.

### Issue 8: TUI event emission from streams context
The `observe` callback runs in `Async Poll`. Writing to the event queue
(`send queue event`) is also `Async`. But `putEvent` expects `NoExcept`.

**Workaround:** The `observe` callback is in `Async Poll [Errno]`, but
`send` returns `Async Poll [Errno] Bool`. Use `weakenErrors` or ignore
the result.

### Issue 9: Scope management with `acquire`
Resources acquired with `acquire` are released when the scope closes.
In `parJoin`, each inner stream runs in its own scope. Make sure
resources are acquired within the correct scope.

**Workaround:** Use `newScope` if needed to create a nested scope.

### Issue 10: `spawnProcess` in `IO` vs `Async`
Process spawning (fork/exec) is inherently blocking and should be done in `IO`.
But the stream runs in `Async`. Need to bridge with `exec . liftIO`.

**Workaround:** Do the spawn in an `exec (liftIO $ ...)` action at the
beginning of the Pull, then transition to async streaming.

## Rollback Plan

If the migration encounters insurmountable issues:
1. Revert changes to `amon.ipkg` (remove `streams`, `streams-posix` dependencies)
2. Restore original `Monitor/Process.idr` and `Monitor/Source.idr` from git
3. The old polling-based approach will continue to work

Keep the old code in a separate branch (`streams-migration`) until the new
implementation is thoroughly tested.

## Success Criteria

- [ ] `idris2 --build amon.ipkg` compiles without errors
- [ ] `./build/exec/amon` runs and shows the TUI
- [ ] All tasks in `tasks.json` execute correctly
- [ ] Task output appears in the TUI in real-time
- [ ] Log files are created with `[START]`/`[END]` markers
- [ ] ANSI escape sequences are stripped in the TUI display
- [ ] Log files preserve raw ANSI sequences
- [ ] Worker pool respects `maxWorkers` limit
- [ ] Queued tasks start when slots free up
- [ ] Process exit codes are reported correctly
- [ ] `zrun --screen` shows correct output
- [ ] No memory leaks (FDs are closed properly)

# Review

## Factual Corrections

### Logging architecture mismatch (Step 1.4, Phase 3)

The document describes log I/O as a major rewrite target, but mischaracterizes the current architecture. The TUI code path does NOT use `openLogFile` or `writeLogChunk` — those functions are orphaned (defined in `Process.idr:106-117` and `Process.idr:72-76` but never called from TUI code). The actual TUI logging works entirely through shell `tee` injected into the command string in `spawnCmd` (`Process.idr:123-128`). The only Idris-side log function called from the TUI path is `writeLogFooter` (`Source.idr:47,60,76`), which appends the `[END]` footer.

**Correction:** The `tee`-based approach means the log file body is written by a separate process (the `tee` child), not by the Idris parent. Removing `tee` and moving logging into Idris is a genuine architectural change, not a refactor. The orphaned `openLogFile`/`writeLogChunk` can be deleted without impacting current behavior.

### `ProcInfo.logPath` vs actual logging

`spawnCmd` stores `task.logFile` into `ProcInfo.logPath` (`Process.idr:169`), which is used by `pollOne` to call `writeLogFooter`. However, the log file body is written by `tee` in the shell, NOT by the Idris code. `writeLogFooter` opens the file in append mode and writes the `[END]` line. This means the current system has a dependency on `tee` being available in `PATH`, and the log file format depends on shell behavior (the `[START]` header is written by `echo` in the shell command, not by Idris code).

### `writeLogFooter` called inside `try [onErrno]` block

`pollOne` calls `weakenErrors $ liftIO $ writeLogFooter ...` at lines 47, 60, 76 of `Source.idr`, all inside `try [onErrno]`. This is the exact anti-pattern warned about in `AGENTS.md` ("Adding `weakenErrors` calls inside a `try [handler]` block changes the error type from `[Errno]` to a broader type, causing unification failures"). The migration should address this by restructuring so footer writes happen outside any `try` block.

## Critical Type Issues in the Proposed Approach

### `>>` discards output — fundamental misunderstanding of Pull sequencing (Step 1.3)

The document proposes at line 223:
```idris
bytes readFd 4096  -- Pull (Async Poll) ByteString [Errno] ()
  >>               -- monadic bind: after stream ends,
  waitpidAndReturn  -- Pull (Async Poll) ByteString [Errno] (Int, Maybe String)
```

This is incorrect. In a `Pull` monad, `p1 >> p2` produces a Pull whose output type is the output type of `p2`. The ByteStrings emitted by `bytes` would be the output of the combined Pull, but they'd be consumed by the downstream consumer (e.g., `drain`), NOT passed through to `waitpidAndReturn`. The `>>` operator sequences the EFFECTS, and the output flows to whatever consumes the combined Pull.

**The real issue:** If the consumer of `spawnProcess` is `parJoin` + `drain`, the ByteString output IS consumed. But `waitpidAndReturn` would run AFTER all bytes are emitted, and its result `(Int, Maybe String)` would be the final result of the Pull, NOT emitted as output. This actually works for `drain` (which ignores output), but the types don't match: `drain` expects `Pull f Void es ()`, while the Pull above has result type `(Int, Maybe String)`.

**Correction:** Use `observe` to capture the exit code as a side effect, or use a ref/mutvar to store it, then return `()` from the Pull:
```idris
spawnProcess task queue = do
  (readFd, pid, logFd) <- exec $ liftIO $ setupProcess task
  observe emitTUIEvent $ bytes readFd 4096
  (_, status) <- exec $ liftIO $ waitpid pid WNOHANG
  exec $ liftIO $ emitJobFinished task status queue
  pure ()  -- drain expects Void output and () result
```

### Error type on `observe` callback (Step 1.5)

The `observe` callback type is `(o -> f es ())`. The `emitTUIEvents` call writes to an event queue channel, which can fail (full channel, closed channel). The callback error type must match the Pull's error type `[Errno]`, but channel errors are NOT `Errno` — they're a different error type.

**Correction:** The `observe` callback will need `weakenErrors` or equivalent to suppress channel errors, or the Pull error type needs to be broadened to include both `Errno` and channel errors. The document acknowledges this at Issue 8 but doesn't reflect it in the code sketches, which show bare `emitLine` calls without error handling.

### `lines` + `UTF8.decode` composition order (Step 1.5)

The document debates line-breaking order extensively (lines 278-339) but never reaches a clean final pipeline. The key constraint:

1. `FS.Bytes.lines` operates on `ByteString` — it splits on `\n` bytes (0x0a)
2. `UTF8.decode` converts `ByteString` → `String`

If you decode first then line-break: you lose the ability to split on raw bytes efficiently.
If you line-break first then decode: you get `(List ByteString)` per chunk, each element is a line in raw bytes.

The final refined version at line 787 uses:
```idris
observe (\lineList => for_ lineList $ \line => ...) $ lines $ bytes readFd 4096
```

This is the correct order. However, there's a subtlety: `FS.Bytes.lines` splits on `\n` (0x0a) but does NOT strip `\r` (0x0d). Windows-style `\r\n` line endings will leave trailing `\r` on each line. The current `stripAnsi` operates on `String` and does NOT strip `\r` either (it only handles `\r` as a cursor column reset at line 210 of `Process.idr`). So this is consistent with current behavior, but worth documenting explicitly.

### Partial line handling at stream end

The document states at lines 744-757 that `FS.Bytes.lines` "emits any remaining partial line via the `last` function." This claim should be verified against the actual `streams` library implementation. If `scanFull` does NOT flush remaining state on stream termination, the final incomplete line will be silently dropped. The current code handles this in `pollOne` (line 38-40): on `NoData`/`EOI`, it calls `splitOutput p.pending ""` to flush the partial line. Any replacement must replicate this behavior.

## spawnCmd Responsibilities Not Accounted For (Step 1.3)

The document describes `spawnProcess` as replacing `spawnCmd`, but `spawnCmd` (`Process.idr:120-169`) does more than the plan accounts for:

1. **`blockingIO` handling** (`Process.idr:157-159`): When `task.blockingIO` is `Just True`, stdin is redirected to `/dev/null`. The plan doesn't mention this.
2. **Non-blocking FD setup** (`Process.idr:165-168`): The read FD is set to non-blocking via `fcntl`. `FS.Posix.bytes` may or may not require this — verify that `readnb` (used internally by `bytes`) works on blocking FDs.
3. **`execvp` fallback** (`Process.idr:161-164`): If `execvp` fails, the child calls `_exit(127)`. The parent has no way to detect this vs. normal exit.

## Minor Issues

### Typo at line 194

```idris
```idras
```
Should be `idris`.

### Typo at line 309

"stream combator" → "stream combinator"

### `cstr_timestamp` thread safety (Phase 4)

`cstr_timestamp` uses a static buffer (`static char buf[64]`). While the current single-threaded code is fine, the streams library may invoke callbacks from multiple fibers within the epoll loop. If `cstr_timestamp` is called concurrently, the static buffer will be corrupted. The plan should either replace it with a thread-safe alternative or document this limitation.

### `parJoin` output type mismatch with `drain`

The document's `resultsSource` sketch at line 542 uses `drain $ parJoin maxWorkers outer`. `drain` has type `Pull f o es () -> Pull f Void es ()`. It consumes all output. But `parJoin` produces `AsyncStream Poll [Errno] ()` (output type `()`). So `drain` would produce `Pull (Async Poll) Void [Errno] ()`. Then `pull` gives `Async Poll [] (Outcome [Errno] ())`.

This chains correctly, BUT: the inner streams (`processPull`) have output type `()`. `parJoin` merges their output. If `processPull` emits `()` values (which it does implicitly through the `do` block), `parJoin` produces a stream of `()`. The `drain` consumes them. This works but is wasteful — each inner stream completion emits a `()` that gets thrown away.

**Better approach:** Use `foreach (const $ pure ())` or a purpose-built combinator instead of `drain`, to make the intent clearer. Or restructure `processPull` to not emit output at all (use `observe` for all side effects and `pure ()` at the end).

### `EventSource` termination semantics

The current `resultsSource` is an infinite loop (`loop` recurses forever). The proposed replacement terminates when `pull` completes (all tasks done). This means the TUI event source will shut down when all tasks finish. The TUI framework (`asyncMain`) may not handle event source termination gracefully — it might exit or hang. The current code's infinite loop keeps the TUI alive.

**Correction:** The new `resultsSource` should either loop indefinitely after all tasks complete (emitting nothing), or the `Main.idr` should handle graceful shutdown separately. Consider adding an explicit "all done" signal or keeping a keep-alive source.

### `maxWorkers` as runtime vs compile-time value

`parJoin` takes a `Nat` literal (compile-time) or requires an `IsSucc` proof. The current `maxWorkers` is a runtime variable (`let maxWorkers = 3` in `Main.idr`). To use `parJoin`, it must be either hardcoded as a literal or passed with an explicit proof term. The document mentions this at Issue 2 but doesn't update the code sketches to reflect it.

## Summary of Required Corrections

| Location | Issue | Severity |
|----------|--------|-----------|
| Step 1.3, line 223 | `>>` sequencing — exit code result type incompatible with `drain` | Critical |
| Step 1.5, line 415-427 | `observe` callback error type mismatch (channel vs Errno) | Critical |
| Phase 3 | Orphaned functions (`openLogFile`, `writeLogChunk`) not identified as dead code | Minor |
| Step 1.3 | Missing `blockingIO` and non-blocking FD setup from `spawnCmd` | Moderate |
| Step 2.1, line 542 | `EventSource` termination — TUI may exit when all tasks done | Moderate |
| Step 1.3 | Partial line flush at EOF not addressed | Moderate |
| Throughout | `\r\n` line ending handling not mentioned | Minor |
| Phase 4 | `cstr_timestamp` static buffer thread safety | Minor |
| Step 2.1 | `maxWorkers` compile-time requirement not reflected in code | Minor |

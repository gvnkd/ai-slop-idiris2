# Issues

## Stuck tasks in async read loop — FIXED

**Severity:** Critical (FIXED)  
**Fixed in:** `pipe2` + `O_CLOEXEC` patch in `spawnProcessSetup`

### Root Cause

The Chez Scheme runtime forks additional OS processes for fiber scheduling.
These children inherit all open pipe fds from the parent. When a pipe's write
end is inherited by a Chez worker, the read end never sees EOF even after our
direct child process exits.

### Fix

Replace `pipe()` with `pipe2(fdarray, O_CLOEXEC)` (flag value 524288 / 0x80000).
Both pipe fds are created with the close-on-exec flag. When our child process
calls `execvp()`, the write fd is automatically closed by the kernel regardless
of what other processes hold it. The `dup2(writeFd, 1/2)` in the child clears
CLOEXEC on the new stdout/stderr, so the exec'd command can still write output.

Confirmed working: 20/20 runs of the PipeLeak reproducer (20 tasks, parJoin 3)
and 3/3 runs of the full amon TUI completed without stuck tasks.

### Files changed

- `src/Monitor/ProcessStream.idr`: `prim__pipe` → `prim__pipe2` with `O_CLOEXEC`
- `src/PipeLeak.idr`: minimal reproducer (also uses `pipe2`)

---

## `parJoin` error propagation cancels sibling fibers

**Severity:** Medium  
**Introduced by:** The cancellation feature (`onCancel`)

When `processPull` runs inside `parJoin`, any `Errno` error (e.g., from
`waitpid` or `kill`) propagates as a stream error. `parJoin` interprets this
as a fatal error and cancels all other running inner streams. This causes
the `onCancel` handler to fire for ALL tasks (not just the one that errored),
marking them as CANCELLED.

This is why the cancellation feature (`onCancel` + `x` key) was removed from
`processPull` in commit `6e61826`. To properly implement cancellation, we
need to either:
- Suppress all errors within each fiber so `parJoin` never sees them
- Use a different concurrency primitive that doesn't cancel siblings on error
- Implement the BQueue-based worker architecture with proper async scheduling

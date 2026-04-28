# Issues

## Stuck tasks in async read loop (pre-existing, critical)

**Severity:** Critical  
**Affected:** All versions (confirmed on commit `38d9d6d` and later)

### Symptoms

Some child processes get stuck in `[R]` (RUNNING) state indefinitely. The async
read loop (`asyncReadLoop` in `ProcessStream.idr`) never sees EOF on the pipe,
so the fiber hangs forever waiting for `asyncPollFd` to return.

In practice, tasks that finish quickly (e.g., `timeout 1s sleep 0.5`) are most
likely to get stuck, while longer-running tasks (e.g., 30s watch.sh) complete
normally. This is counterintuitive and suggests a race condition.

### Root Cause

The Chez Scheme runtime (used by Idris 2 on the default backend) creates
additional OS-level processes via `fork()` for its own purposes (fiber
scheduling, GC, etc.). These child processes **inherit all open file
descriptors** from the parent, including pipe write ends created by our
`spawnProcessSetup`.

When our code does:
1. `pipe()` → creates pipe with read/write fds
2. `fork()` → child process created
3. Parent closes write fd
4. Child: dup2 write fd to stdout/stderr, close original, execvp

The problem: OTHER scheme runtime child processes (not our direct child) also
hold the pipe write fds. When our direct child exits, its write fds close, but
the runtime's child processes still hold write fds open. The pipe therefore
never gets POLLHUP, and `asyncPollFd` never fires.

### Evidence

```
# Process 45066 (main amon) has pipe read ends:
lr-x------ 5 -> pipe:[235406]   (Watch)
lr-x------ 7 -> pipe:[118383]   (Quick Sleep) ← stuck
lr-x------ 9 -> pipe:[118385]   (Missing Binary)

# Process 45086 (scheme runtime child) holds WRITE ends of Quick Sleep pipe:
l-wx------ 1 -> pipe:[118383]   ← keeps pipe open!
l-wx------ 2 -> pipe:[118383]   ← keeps pipe open!

# Process 45086 is a live scheme process, NOT a zombie:
PID 45086, PPID 45066, State S, Command: amon.so
```

The write end of pipe 118383 is held by process 45086 (a forked scheme worker)
on fds 1 and 2. Even though our direct child process exited, the pipe remains
open because another process holds the write fd.

### Why `closeFdsFrom` doesn't fully fix it

The `closeFdsFrom 3` call in our child process (added in commit `6e61826`)
closes fds 3-1023 in our direct child before `execvp`. This prevents the
exec'd command from inheriting old pipes. However, it does NOT affect the
scheme runtime's OTHER forked processes — those were forked independently and
inherited the parent's full fd table.

### Potential fixes

1. **Use `pipe2()` with `O_CLOEXEC`** — pipes created with close-on-exec flag
   would automatically close when any child calls `execvp`. This only helps
   if the scheme runtime children eventually exec, which may not be the case.

2. **Use `posix` library's pipe/fork/exec** instead of raw FFI — the posix
   library may have better integration with the scheme runtime's fd management.

3. **Use `System.system` or `System.Concurrency.fork`** instead of raw
   `fork()+execvp()` — higher-level APIs may handle fd cleanup properly.

4. **Close ALL pipe write fds in the parent BEFORE fork** — create pipes,
   fork, pass write fd via inheritance only in the child. But this requires
   restructuring the fork/exec pattern.

5. **Switch to `System.File.Process.popen`-style process management** — use
   Idris's built-in process management instead of rolling our own fork/exec.

6. **Investigate Chez Scheme's fd handling** — determine why the runtime forks
   additional processes and whether there's a way to prevent fd inheritance
   (e.g., pthread_atfork handlers, or scheme runtime configuration).

### Reproduction

```bash
./zrun                          # Start amon in headless zellij
# Wait ~40 seconds for all tasks
./zrun --screen 0               # Some tasks will be stuck at [R]
```

The "Quick Sleep" task (timeout 1s, sleep 0.5) is consistently stuck.

### Workaround

The `closeFdsFrom` fix reduces the frequency of stuck tasks but doesn't
eliminate the issue. Killing the amon process also kills all children,
freeing resources.

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

module Monitor.Main

import TUI.View
import TUI.MainLoop
import TUI.MainLoop.Async
import TUI.Event
import TUI.Key
import IO.Async.Loop.Posix
import IO.Async.Loop.Epoll
import System
import Data.List
import Data.Maybe
import Monitor.Types
import Monitor.Provider
import Monitor.Process
import Monitor.Source
import Monitor.View
import Monitor.Handler

covering
run : IO ()
run = do
  ignore $ system "mkdir -p logs"
  mThreads <- getEnv "IDRIS2_ASYNC_THREADS"
  when (isNothing mThreads) $
    ignore $ setEnv "IDRIS2_ASYNC_THREADS" "1" False
  Just tasks <- loadTasks "tasks.json"
    | Nothing => die "Failed to load tasks.json"
  let maxWorkers = 3
  let entries = toJobEntries tasks
  let initState = initialState entries
  let mainLoop = asyncMain {evts = [JobUpdate, Key]}
                    [resultsSource 3 tasks]
  Prelude.ignore $ runView mainLoop handler initState

covering
main : IO ()
main = run
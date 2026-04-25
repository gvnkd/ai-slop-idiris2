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
  Just tasks <- loadTasks "tasks.json"
    | Nothing => die "Failed to load tasks.json"
  let maxWorkers = 3
  let (initial, queued) = splitAt (cast maxWorkers) tasks
  let entries = toJobEntries tasks
  procs <- mapMaybe id <$> traverse spawnCmd initial
  let runningEntries = map (\e => { status := RUNNING } e) $ take (length initial) entries
  let allEntries = runningEntries ++ drop (length initial) entries
  let initState = initialState allEntries
  let mainLoop = asyncMain {evts = [JobUpdate, Key]} [resultsSource procs queued]
  Prelude.ignore $ runView mainLoop handler initState

covering
main : IO ()
main = run

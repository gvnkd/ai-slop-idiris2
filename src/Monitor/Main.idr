module Monitor.Main

import TUI.View
import TUI.MainLoop
import TUI.MainLoop.Async
import TUI.Event
import TUI.Key
import IO.Async.Loop.Posix
import IO.Async.Loop.Epoll
import System
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
  let entries = toJobEntries tasks
  procs <- mapMaybe id <$> traverse spawnCmd tasks
  let initState = initialState (map (\e => { status := RUNNING } e) entries)
  let mainLoop = asyncMain {evts = [JobUpdate, Key]} [resultsSource procs]
  Prelude.ignore $ runView mainLoop handler initState

covering
main : IO ()
main = run

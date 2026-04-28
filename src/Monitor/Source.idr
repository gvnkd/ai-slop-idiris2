module Monitor.Source

import TUI.MainLoop.Async
import IO.Async
import IO.Async.Util
import IO.Async.Posix
import Monitor.Types
import Monitor.ProcessStream
import System.Posix.Process
import System.Posix.Errno
import Data.List
import Data.Maybe
import FS
import FS.Concurrent
import FS.Pull

import public Monitor.Process

public export
covering
resultsSource : Has JobUpdate evts
               => (maxWorkers : Nat)
               -> {auto 0 prf : IsSucc maxWorkers}
               -> List ProcessTask
               -> EventSource evts
resultsSource maxWorkers tasks queue = assert_total $ do
  outcome <- pull $ runAllTasks maxWorkers tasks queue
  case outcome of
    Succeeded _ => pure ()
    Canceled    => pure ()
    Error _     => pure ()
  loop
  where
    loop : NoExcept ()
    loop = assert_total $ do
      sleep 1.s
      loop

module Monitor.Source

import TUI.MainLoop.Async
import IO.Async
import IO.Async.Util
import IO.Async.BQueue
import Monitor.Types
import Monitor.ProcessStream
import Data.List
import Data.Maybe

import public Monitor.Process

public export
covering
resultsSource : Has JobUpdate evts
               => (maxWorkers : Nat)
               -> {auto 0 prf : IsSucc maxWorkers}
               -> List ProcessTask
               -> EventSource evts
resultsSource maxWorkers tasks queue = do
  q <- bqueue maxWorkers
  let dispatcher : NoExcept ()
      dispatcher = do
        traverse_ (enqueue q . Just) tasks
        traverse_ (\_ => enqueue q Nothing)
                  (replicate maxWorkers ())
  let worker : NoExcept ()
      worker = do
        mTask <- dequeue q
        case mTask of
          Nothing   => pure ()
          Just task => processPull task queue >> worker
  let workers = replicate maxWorkers worker
  ignore $ parseq (dispatcher :: workers)
  putEvent queue $ AllDone False
  loop
  where
    loop : NoExcept ()
    loop = do
      sleep 1.s
      loop

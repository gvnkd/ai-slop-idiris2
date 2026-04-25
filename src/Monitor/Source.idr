module Monitor.Source

import TUI.MainLoop.Async
import IO.Async
import IO.Async.Util
import IO.Async.Posix
import Monitor.Types
import Monitor.Process
import System.Posix.File
import System.Posix.Process
import System.Posix.Errno
import Data.List
import Data.Maybe

emitLines : Has JobUpdate evts => String -> List String -> EventQueue evts -> NoExcept ()
emitLines name lines queue =
  let logLines = map (MkLogLine "out>") $ filter (\l => length l > 0) lines
  in when (not $ null logLines) $ putEvent queue $ JobOutput name logLines

public export
covering
resultsSource : Has JobUpdate evts => List ProcInfo -> List ProcessTask -> EventSource evts
resultsSource procs taskQueue queue = loop procs taskQueue
  where
    onErrno : Errno -> NoExcept (Maybe ProcInfo)
    onErrno _ = pure Nothing

    covering
    pollOne : ProcInfo -> EventQueue evts -> NoExcept (Maybe ProcInfo)
    pollOne p queue = try [onErrno] $ do
      res <- readres p.fd String 4096
      case res of
        NoData => do
          (retPid, status) <- waitpid (the PidT $ cast p.pid) WNOHANG
          if retPid == 0
            then pure (Just p)
            else do
              close p.fd
              let (complete, _) = splitOutput p.pending ""
              weakenErrors $ emitLines p.name complete queue
              let jobStatus = case status of
                                Exited code => if code == 0 then SUCCESS else FAILED
                                _ => FAILED
              weakenErrors $ putEvent queue $ JobFinished p.name jobStatus
              pure Nothing
        EOI => do
          (_, status) <- waitpid (the PidT $ cast p.pid) WNOHANG
          close p.fd
          let (complete, _) = splitOutput p.pending ""
          weakenErrors $ emitLines p.name complete queue
          let jobStatus = case status of
                            Exited code => if code == 0 then SUCCESS else FAILED
                            _ => FAILED
          weakenErrors $ putEvent queue $ JobFinished p.name jobStatus
          pure Nothing
        Res chunk => do
          let cleanChunk = stripAnsi chunk
          let (complete, pending) = splitOutput p.pending cleanChunk
          weakenErrors $ emitLines p.name complete queue
          if null complete && length pending > 0
            then do
              weakenErrors $ emitLines p.name [pending] queue
              pure $ Just ({ pending := "" } p)
            else pure $ Just ({ pending := pending } p)
        Closed => do
          close p.fd
          weakenErrors $ putEvent queue $ JobFinished p.name FAILED
          pure Nothing
        Interrupted => pure (Just p)

    covering
    pollAll : List ProcInfo -> EventQueue evts -> NoExcept (List ProcInfo)
    pollAll [] _ = pure []
    pollAll (p :: ps) queue = do
      mp <- pollOne p queue
      ps' <- pollAll ps queue
      pure $ maybe ps' (:: ps') mp

    covering
    loop : List ProcInfo -> List ProcessTask -> NoExcept ()
    loop procs taskQueue = do
      sleep 100.ms
      newProcs <- pollAll procs queue
      let freed = length procs `minus` length newProcs
      let (toSpawn, remainingQueue) = splitAt (cast freed) taskQueue
      spawned <- mapMaybe id <$> traverse (liftIO . spawnCmd) toSpawn
      let allProcs = spawned ++ newProcs
      loop allProcs remainingQueue

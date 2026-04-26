module Monitor.ProcessStream

import Protocol
import Monitor.Types
import Monitor.Process
import TUI.MainLoop.Async
import Data.String
import Data.Maybe
import Data.Bits
import Data.C.Array
import Data.C.Ptr
import Data.ByteString
import Data.Buffer
import System.Posix.File.FileDesc
import IO.Async
import IO.Async.Posix
import IO.Async.Util
import System.Posix.File
import System.Posix.Process
import System.Posix.Errno
import FS
import FS.Concurrent
import FS.Bytes
import FS.Pull
import FS.Resource

%default total

%foreign "C:pipe,libc"
prim__pipe : AnyPtr -> PrimIO CInt

%foreign "C:close,libc"
prim__close : Int -> PrimIO Int

%foreign "C:open,libc"
prim__open : String -> Int -> PrimIO Int

%foreign "C:open,libc"
prim__open3 : String -> Int -> Int -> PrimIO Int

%foreign "C:fork,libc"
prim__fork : PrimIO Int

%foreign "C:dup2,libc"
prim__dup2 : Int -> Int -> PrimIO Int

%foreign "C:execvp,libc"
prim__execvp : String -> AnyPtr -> PrimIO Int

%foreign "C:_exit,libc"
prim__exit : Int -> PrimIO ()

%foreign "C:fcntl,libc"
prim__fcntl : Int -> Int -> PrimIO Int

%foreign "C:fcntl,libc"
prim__fcntl_set : Int -> Int -> Int -> PrimIO Int

||| Record to hold process resources for cleanup.
public export
record ProcessResources where
  constructor MkProcessResources
  readFd   : Int
  logFd    : Maybe Int

||| Close a file descriptor (async wrapper).
closeFdAsync : Int -> Async Poll [] ()
closeFdAsync fd = liftIO $ do
  ignore $ primIO $ prim__close fd
  pure ()

||| Spawn a child process, return (readFd, pid, maybeLogFd).
spawnProcessSetup : ProcessTask -> IO (Maybe (Int, Int, Maybe Int))
spawnProcessSetup task = do
  let baseCmd = "timeout " ++ show task.timeout ++ "s " ++ task.path
                ++ " " ++ unwords task.args
  pipeArr <- malloc Fd 2
  rc <- primIO $ prim__pipe (unsafeUnwrap pipeArr)
  if rc < 0
    then do free pipeArr; pure Nothing
    else do
      Just buf <- newBuffer 8 | Nothing => do
        free pipeArr; pure Nothing
      primIO $ prim__copy_pb (unsafeUnwrap pipeArr) buf 8
      free pipeArr
      readBits <- getBits32 buf 0
      writeBits <- getBits32 buf 4
      let readFd  = the Int (cast readBits)
          writeFd = the Int (cast writeBits)
      childPid <- primIO prim__fork
      if childPid == 0
        then do
          _ <- primIO $ prim__close readFd
          _ <- primIO $ prim__dup2 writeFd 1
          _ <- primIO $ prim__dup2 writeFd 2
          _ <- primIO $ prim__close writeFd
          let blk = fromMaybe True task.blockingIO
          when blk $ do
            devnull <- primIO $ prim__open "/dev/null" 0
            _ <- primIO $ prim__dup2 devnull 0
            _ <- primIO $ prim__close devnull
            pure ()
          argsArr <- fromList [Just "sh", Just "-c", Just baseCmd, Nothing]
          _ <- primIO $ prim__execvp "/bin/sh" (unsafeUnwrap argsArr)
          free argsArr
          primIO $ prim__exit 127
          pure Nothing
        else do
          _ <- primIO $ prim__close writeFd
          flags <- primIO $ prim__fcntl readFd 3
          _ <- primIO $ prim__fcntl_set readFd 4 (flags .|. 2048)
          logFd <- maybeOpenLog task.logFile
          pure $ Just (readFd, childPid, logFd)
      where
        maybeOpenLog : Maybe String -> IO (Maybe Int)
        maybeOpenLog Nothing = pure Nothing
        maybeOpenLog (Just path) = do
          fd <- primIO $ prim__open3 path 1089 384
          if fd < 0 then pure Nothing
            else do
              ts <- getCurrentTimeStr
              let header := "[START] " ++ ts ++ "\n"
              _ <- writeToFd fd header
              pure $ Just fd

||| Emit TUI events for lines from a process.
emitTUILines : Has JobUpdate evts
              => String
              -> List String
              -> EventQueue evts
              -> Async Poll [] ()
emitTUILines name lines queue =
  let logLines = map (MkLogLine "out>")
                  $ filter (\l => length l > 0) lines
   in when (not $ null logLines)
        $ putEvent queue $ JobOutput name logLines

||| Process a chunk of line-ByteStrings: write to log, emit TUI events.
covering
processLineChunks : Has JobUpdate evts
                   => String
                  -> Maybe Int
                  -> EventQueue evts
                  -> List ByteString
                  -> Async Poll [Errno] ()
processLineChunks taskName mlogFd queue lineBsList = do
  for_ lineBsList $ \lineBs => do
    case mlogFd of
      Just lfd => do
        let logStr = toString lineBs ++ "\n"
        ignore $ liftIO $ writeToFd lfd logStr
        pure ()
      Nothing  => pure ()
    let decoded = toString lineBs
    let clean = stripAnsi decoded
    when (length clean > 0)
      $ weakenErrors $ emitTUILines taskName [clean] queue

||| Read ByteString chunks from an FD until EOF.
readBytesFromFd : Int -> Bits32 -> AsyncStream Poll [Errno] ByteString
readBytesFromFd fd bufSize =
  unfoldEvalMaybe $ ByteString.nonEmpty
    <$> readnb (MkFd $ cast fd) ByteString bufSize

||| Write log footer for a process.
writeProcessFooter : Maybe Int -> Int -> Async Poll [Errno] ()
writeProcessFooter Nothing _ = pure ()
writeProcessFooter (Just lfd) exitCode = do
  ts <- liftIO getCurrentTimeStr
  let statusStr = if exitCode == 0 then "SUCCESS" else "FAILED"
  let footer = "[END] " ++ ts ++ " " ++ statusStr ++ "\n"
  ignore $ liftIO $ writeToFd lfd footer
  pure ()

||| Inner body of processPull after successful spawn.
covering
processPullBody : Has JobUpdate evts
                 => ProcessTask
                -> EventQueue evts
                -> Int    -- readFd
                -> Int    -- pid
                -> Maybe Int  -- logFd
                -> AsyncStream Poll [Errno] ()
processPullBody task queue readFd pid logFd = assert_total $ do
  ignore $ exec $ weakenErrors $ putEvent queue $ JobFinished task.name RUNNING

  _ <- acquire (pure (MkProcessResources readFd logFd))
          $ \(MkProcessResources rfd mlogFd) => do
              weakenErrors $ closeFdAsync rfd
              case mlogFd of
                Just lfd => weakenErrors $ closeFdAsync lfd
                Nothing  => pure ()

  foreach (processLineChunks task.name logFd queue)
          $ lines $ readBytesFromFd readFd 4096

  (_, status) <- waitpid (the PidT $ cast pid) WNOHANG
  let exitCode : Int
      exitCode = case status of
                    Exited code => cast code
                    _          => 127
  let jobStatus = if exitCode == 0 then SUCCESS else FAILED

  exec $ writeProcessFooter logFd exitCode
  ignore $ exec $ weakenErrors $ putEvent queue $ JobFinished task.name jobStatus

||| Per-process Pull: spawns, streams output, emits events, cleans up.
covering
processPull : Has JobUpdate evts
            => ProcessTask
            -> EventQueue evts
            -> AsyncStream Poll [Errno] ()
processPull task queue = assert_total $ do
  maybeRes <- exec $ liftIO $ spawnProcessSetup task
  case maybeRes of
    Nothing => pure ()
    Just (readFd, pid, logFd) =>
      processPullBody task queue readFd pid logFd

||| Build an outer stream of per-process streams, run with parJoin.
export
runAllTasks : Has JobUpdate evts
            => (maxWorkers : Nat)
            -> {auto 0 prf : IsSucc maxWorkers}
            -> List ProcessTask
            -> EventQueue evts
            -> Pull (Async Poll) Void [Errno] ()
runAllTasks maxWorkers tasks queue =
  drain $ parJoin maxWorkers outer
  where
    outer : AsyncStream Poll [Errno] (AsyncStream Poll [Errno] ())
    outer = emits $ map (\t => processPull t queue) tasks
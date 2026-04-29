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
import Data.IORef
import System.Posix.File.ReadRes
import Data.Vect
import System.Posix.File.FileDesc
import IO.Async
import IO.Async.Loop.PollH
import IO.Async.Loop.Posix
import IO.Async.Posix
import IO.Async.Util
import System.Posix.Poll.Types
import System.Posix.File
import System.Posix.File.FileDesc
import System.Posix.Process
import System.Posix.Errno
import System.Posix.Signal
import System.File
import FS
import FS.Concurrent
import FS.Pull
import FS.Resource
import Data.ByteVect

%default total

%foreign "C:pipe2,libc"
prim__pipe2 : AnyPtr -> Int -> PrimIO CInt

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

%foreign "C:read,libc"
prim__sys_read : Int -> Buffer -> Int -> PrimIO Int

public export
record ProcessResources where
  constructor MkProcessResources
  readFd   : Int
  logFd    : Maybe Int
  pid      : Int

closeFdAsync : Int -> Async Poll [] ()
closeFdAsync fd = liftIO $ ignore $ primIO $ prim__close fd

%default total

killChild : Int -> Async Poll [Errno] ()
killChild pid = kill (the PidT $ cast pid) SIGTERM

covering
closeFdsFrom : Int -> IO ()
closeFdsFrom n =
  when (n < 1024) $ do
    ignore $ primIO $ prim__close n
    closeFdsFrom (n + 1)

covering
spawnProcessSetup : ProcessTask -> IO (Maybe (Int, Int, Maybe Int))
spawnProcessSetup task = do
  let baseCmd = "timeout " ++ show task.timeout ++ "s " ++ task.path
                ++ " " ++ unwords task.args
  pipeArr <- malloc Fd 2
  rc <- primIO $ prim__pipe2 (unsafeUnwrap pipeArr) 524288
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
          closeFdsFrom 3
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
              let header = "[START] " ++ ts ++ "\n"
              _ <- writeToFd fd header
              pure $ Just fd

splitOutputLocal : String -> String -> (List String, String)
splitOutputLocal buf chunk = go [] [] (unpack (buf ++ chunk))
  where
    go : List String -> List Char -> List Char -> (List String, String)
    go linesAcc lineBuf []        = (reverse linesAcc, pack (reverse lineBuf))
    go linesAcc lineBuf (c :: cs) =
      if c == '\n'
         then go ((pack (reverse lineBuf)) :: linesAcc) [] cs
         else go linesAcc (c :: lineBuf) cs

bits8ToChar : Bits8 -> Char
bits8ToChar b = cast b

byteStringToString : ByteString -> String
byteStringToString bs = pack $ map bits8ToChar $ ByteString.unpack bs

covering
emitLine : Has JobUpdate evts
          => String -> Maybe Int -> EventQueue evts -> String
          -> Async Poll [Errno] ()
emitLine taskName mLogFd queue line = do
  case mLogFd of
    Just lfd => ignore $ liftIO $ writeToFd lfd (line ++ "\n")
    Nothing  => pure ()
  let clean = stripAnsi line
  when (length clean > 0) $
    weakenErrors $ putEvent queue $ JobOutput taskName [MkLogLine "" clean]

writeProcessFooter : Maybe Int -> Int -> Async Poll [Errno] ()
writeProcessFooter Nothing _ = pure ()
writeProcessFooter (Just lfd) exitCode = do
  ts <- liftIO getCurrentTimeStr
  let statusStr = if exitCode == 0 then "SUCCESS" else "FAILED"
  let footer = "[END] " ++ ts ++ " " ++ statusStr ++ "\n"
  ignore $ liftIO $ writeToFd lfd footer
  pure ()

covering
readChunkAct : Has JobUpdate evts
              => String -> Maybe Int -> EventQueue evts
              -> Data.IORef.IORef String
              -> ByteString -> Async Poll [Errno] ()
readChunkAct _ _ _ _ (BS 0 _) = pure ()
readChunkAct taskName mLogFd queue bufRef bs = do
  let chunk := byteStringToString bs
  oldBuf <- liftIO $ readIORef bufRef
  let (completeLines, newBuf) = splitOutputLocal oldBuf chunk
  liftIO $ writeIORef bufRef newBuf
  for_ completeLines $ emitLine taskName mLogFd queue

bufToByteString : Buffer -> Int -> IO ByteString
bufToByteString buf len = do
  Just newBuf <- newBuffer len
    | Nothing => pure ByteString.empty
  let ptr := prim__malloc (cast len)
  primIO $ prim__copy_bp buf ptr (cast len)
  primIO $ prim__copy_pb ptr newBuf (cast len)
  primIO $ prim__free ptr
  pure $ unsafeByteString (cast len) newBuf

parameters {auto ep : PollH Poll}

  asyncPollFd : Fd -> PollEvent -> Async Poll [Errno] PollEvent
  asyncPollFd thisFd evt = do
    st <- env
    primAsync $ \cb =>
      primPoll st thisFd evt False $ \result =>
        cb $ case result of
          Right x => Right x
          Left  x => Left (Here x)

  readOneChunk : Int -> Async Poll [Errno] (Int, ByteString)
  readOneChunk rawFd = do
    let fd = MkFd $ cast rawFd
    Just buf <- liftIO $ newBuffer 4096
      | Nothing => pure (-1, ByteString.empty)
    n <- liftIO $ primIO $ prim__sys_read rawFd buf 4096
    if n > 0
      then do
        bs <- liftIO $ bufToByteString buf n
        pure (n, bs)
      else if n == 0
        then pure (0, ByteString.empty)
        else do
          _ <- asyncPollFd fd (POLLIN <+> POLLHUP <+> POLLERR)
          n2 <- liftIO $ primIO $ prim__sys_read rawFd buf 4096
          if n2 > 0
            then do
              bs <- liftIO $ bufToByteString buf n2
              pure (n2, bs)
            else pure (n2, ByteString.empty)

  covering
  asyncReadLoop : Has JobUpdate evts
                  => Int -> String -> Maybe Int -> EventQueue evts
                  -> Data.IORef.IORef String
                  -> Async Poll [Errno] ()
  asyncReadLoop thisFd taskName mLogFd queue bufRef = do
    (n, bs) <- readOneChunk thisFd
    if n <= 0
       then pure ()
       else do
         readChunkAct taskName mLogFd queue bufRef bs
         asyncReadLoop thisFd taskName mLogFd queue bufRef

  covering
  runProcess : Has JobUpdate evts
               => ProcessTask
              -> EventQueue evts
              -> Int
              -> Int
              -> Maybe Int
              -> Async Poll [Errno] ()
  runProcess task queue readFd pid logFd =
    guarantee
      (assert_total $ do
        ignore $ weakenErrors $
          putEvent queue $ JobFinished task.name RUNNING

        bufRef <- liftIO $ newIORef ""

        asyncReadLoop readFd task.name logFd queue bufRef

        remaining <- liftIO $ readIORef bufRef
        when (length remaining > 0) $
          emitLine task.name logFd queue remaining

        (_, status) <- waitpid (the PidT $ cast pid) WNOHANG
        let exitCode : Int
            exitCode = case status of
                           Exited code => cast code
                           _           => 127
        let jobStatus = if exitCode == 0 then SUCCESS else FAILED

        writeProcessFooter logFd exitCode
        ignore $ weakenErrors $
          putEvent queue $ JobFinished task.name jobStatus)
      (do
        weakenErrors $ closeFdAsync readFd
        case logFd of
          Just lfd => weakenErrors $ closeFdAsync lfd
          Nothing  => pure ())

  covering
  processPull : Has JobUpdate evts
                => ProcessTask
                -> EventQueue evts
                -> Async Poll [Errno] ()
  processPull task queue = assert_total $ do
    maybeRes <- liftIO $ spawnProcessSetup task
    case maybeRes of
      Nothing => pure ()
      Just (readFd, pid, logFd) =>
        runProcess task queue readFd pid logFd

  covering
  completionStream : Has JobUpdate evts
                     => EventQueue evts
                     -> AsyncStream Poll [Errno] ()
  completionStream evtQueue = assert_total $ do
    sleep 30.s
    ignore $ exec $ weakenErrors $
      putEvent evtQueue $ AllDone False

  export covering
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
      outer = emits $ map (\t => exec $ processPull t queue) tasks
              ++ [completionStream queue]

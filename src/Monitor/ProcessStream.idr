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
import System.Posix.Process.Flags
import System.Posix.Errno
import System.Posix.Signal
import System.File
import FS
import FS.Concurrent
import FS.Pull
import FS.Resource
import Data.ByteVect

%default total

%foreign "C:amon_cstr_write,amon-idris"
prim__cstr_write : Int -> String -> PrimIO CInt

%foreign "C:amon_spawn_child,amon-idris"
prim__spawn_child : String -> AnyPtr -> Int -> PrimIO CInt

%foreign "C:close,libc"
prim__close : Int -> PrimIO Int

%foreign "C:open,libc"
prim__open3 : String -> Int -> Int -> PrimIO Int

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
spawnProcessSetup : ProcessTask -> IO (Maybe (Int, Int, Maybe Int))
spawnProcessSetup task = do
  let baseCmd = "timeout " ++ show task.timeout ++ "s " ++ task.path
                ++ " " ++ unwords task.args
  let envPrefix = concat $ map (\(k,v) => k ++ "=" ++ v ++ " ") task.envVars
  let fullCmd = if envPrefix == "" then baseCmd else envPrefix ++ baseCmd
  outArr <- malloc Fd 2
  rc <- primIO $ prim__spawn_child fullCmd (unsafeUnwrap outArr) 524288
  if rc < 0
    then do free outArr; pure Nothing
    else do
      Just buf <- newBuffer 8 | Nothing => do
        free outArr; pure Nothing
      primIO $ prim__copy_pb (unsafeUnwrap outArr) buf 8
      free outArr
      readBits <- getBits32 buf 0
      pidBits  <- getBits32 buf 4
      let readFd   = the Int (cast readBits)
          childPid = the Int (cast pidBits)
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

covering
emitLine : Has JobUpdate evts
          => String -> Maybe Int -> EventQueue evts -> String
          -> Async Poll [Errno] ()
emitLine taskName mLogFd queue line = do
  case mLogFd of
    Just lfd => ignore $ liftIO $ writeToFd lfd (line ++ "\n")
    Nothing  => pure ()
  when (length line > 0) $
    weakenErrors $ putEvent queue $ JobOutput taskName [MkLogLine "" line]

writeProcessFooter : Maybe Int -> Int -> Async Poll [Errno] ()
writeProcessFooter Nothing _ = pure ()
writeProcessFooter (Just lfd) exitCode = do
  ts <- liftIO getCurrentTimeStr
  let statusStr = case exitCode of
                       0   => "SUCCESS"
                       124 => "TIMEDOUT"
                       _   => "FAILED"
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
  let chunk := toString bs
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
  drainRemaining : Has JobUpdate evts
                  => Int -> String -> Maybe Int -> EventQueue evts
                  -> Data.IORef.IORef String
                  -> Async Poll [Errno] ()
  drainRemaining fd taskName mLogFd queue bufRef = do
    Just buf <- liftIO $ newBuffer 4096
      | Nothing => pure ()
    n <- liftIO $ primIO $ prim__sys_read fd buf 4096
    if n > 0
      then do
        bs <- liftIO $ bufToByteString buf n
        readChunkAct taskName mLogFd queue bufRef bs
        drainRemaining fd taskName mLogFd queue bufRef
      else
        pure ()

  covering
  waitForChild : PidT -> Async Poll [Errno] (PidT, ProcStatus)
  waitForChild pid = do
    (reaped, status) <- waitpid pid WNOHANG
    if reaped == 0
      then do
        ignore $ sleep 50.ms
        waitForChild pid
      else
        pure (reaped, status)

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
           putEvent queue $ JobStarted task.name pid
         bufRef <- liftIO $ newIORef ""
         readFiber <- start $ asyncReadLoop readFd task.name logFd queue bufRef
         (reaped, status) <- waitForChild (the PidT $ cast pid)
         liftIO $ ignore $ primIO $ prim__close readFd
         let reaped2 = reaped
             status2 = status
         remaining <- liftIO $ readIORef bufRef
         when (length remaining > 0) $
           emitLine task.name logFd queue remaining
         let exitCode : Int
             exitCode = case status of
                             Exited code => cast code
                             _           => 127
         let jobStatus = case exitCode of
                              0   => SUCCESS
                              124 => TIMEDOUT
                              _   => FAILED
         writeProcessFooter logFd exitCode
         ignore $ weakenErrors $
           putEvent queue $ JobFinished task.name jobStatus)
      (do
        weakenErrors $ closeFdAsync readFd
        case logFd of
          Just lfd => weakenErrors $ closeFdAsync lfd
          Nothing  => pure ())

  export covering
  processPull : Has JobUpdate evts
                => ProcessTask
                -> EventQueue evts
                -> Async Poll [] ()
  processPull task queue = assert_total $ do
    maybeRes <- liftIO $ spawnProcessSetup task
    case maybeRes of
      Nothing => putEvent queue $ JobFinished task.name FAILED
      Just (readFd, pid, logFd) =>
        try [onErrno] $ runProcess task queue readFd pid logFd
    where
      onErrno : Errno -> NoExcept ()
      onErrno _ = putEvent queue $ JobFinished task.name FAILED

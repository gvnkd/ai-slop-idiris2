module PipeLeak

import Data.C.Array
import Data.C.Ptr
import Data.Buffer
import Data.Bits
import System
import System.Posix.File.FileDesc
import IO.Async
import IO.Async.Loop.PollH
import IO.Async.Loop.Posix
import IO.Async.Loop.Epoll
import IO.Async.Posix
import IO.Async.Util
import System.Posix.Poll.Types
import System.Posix.Errno
import System.Posix.Signal
import FS
import FS.Pull
import FS.Concurrent

%foreign "C:pipe2,libc"
prim__pipe2 : AnyPtr -> Int -> PrimIO CInt

%foreign "C:close,libc"
prim__close : Int -> PrimIO Int

%foreign "C:fork,libc"
prim__fork : PrimIO Int

%foreign "C:dup2,libc"
prim__dup2 : Int -> Int -> PrimIO Int

%foreign "C:execvp,libc"
prim__execvp : String -> AnyPtr -> PrimIO Int

%foreign "C:_exit,libc"
prim__exit : Int -> PrimIO ()

%foreign "C:read,libc"
prim__sys_read : Int -> Buffer -> Int -> PrimIO Int

covering
closeFdsFrom : Int -> IO ()
closeFdsFrom n =
  when (n < 1024) $ do
    ignore $ primIO $ prim__close n
    closeFdsFrom (n + 1)

covering
spawn : String -> IO (Maybe (Int, Int))
spawn cmd = assert_total $ do
  pipeArr <- malloc Fd 2
  rc <- primIO $ prim__pipe2 (unsafeUnwrap pipeArr) 524288
  if rc < 0
    then do free pipeArr; pure Nothing
    else do
      Just buf <- newBuffer 8
        | Nothing => do free pipeArr; pure Nothing
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
          argsArr <- fromList [Just "sh", Just "-c", Just cmd, Nothing]
          _ <- primIO $ prim__execvp "/bin/sh" (unsafeUnwrap argsArr)
          free argsArr
          primIO $ prim__exit 127
          pure Nothing
        else do
          _ <- primIO $ prim__close writeFd
          pure $ Just (readFd, childPid)

parameters {auto ep : PollH Poll}

  asyncPollFd : Fd -> PollEvent -> Async Poll [Errno] PollEvent
  asyncPollFd thisFd evt = do
    st <- env
    primAsync $ \cb =>
      primPoll st thisFd evt False $ \result =>
        cb $ case result of
          Right x => Right x
          Left  x => Left (Here x)

  covering
  readUntilEof : Int -> (label : String) -> Async Poll [Errno] ()
  readUntilEof fd label = do
    let fdesc = MkFd $ cast fd
    Just buf <- liftIO $ newBuffer 4096
      | Nothing => pure ()
    n <- liftIO $ primIO $ prim__sys_read fd buf 4096
    if n > 0
      then readUntilEof fd label
      else if n == 0
        then liftIO $ putStrLn "[\{label}] EOF received"
        else do
          _ <- asyncPollFd fdesc (POLLIN <+> POLLHUP <+> POLLERR)
          n2 <- liftIO $ primIO $ prim__sys_read fd buf 4096
          if n2 > 0
            then readUntilEof fd label
            else liftIO $ putStrLn "[\{label}] EOF after poll (n=\{show n2})"

  covering
  runOne : String -> Async Poll [Errno] ()
  runOne label = do
    maybeInfo <- liftIO $ spawn label
    case maybeInfo of
      Nothing => liftIO $ putStrLn "[\{label}] spawn failed"
      Just (readFd, pid) => do
        liftIO $ putStrLn "[\{label}] spawned pid=\{show pid} readFd=\{show readFd}"
        readUntilEof readFd label
        liftIO $ ignore $ primIO $ prim__close readFd
        liftIO $ putStrLn "[\{label}] done"

  covering
  runAllPar : (n : Nat) -> {auto 0 prf : IsSucc n} -> List String -> Pull (Async Poll) Void [Errno] ()
  runAllPar n cmds = drain $ parJoin n outer
    where
      outer : AsyncStream Poll [Errno] (AsyncStream Poll [Errno] ())
      outer = emits $ map (\c => exec $ runOne c) cmds

  covering
  runAll : List String -> Pull (Async Poll) Void [Errno] ()
  runAll cmds = runAllPar 3 cmds

covering
showChildren : IO String
showChildren = do
  let cmd = "ps -o pid,ppid,comm --no-headers --ppid=$$ 2>/dev/null"
  res <- system cmd
  pure ""

covering
main : IO ()
main = epollApp $ the (Async Poll [] ()) $ do
  liftIO $ putStrLn "=== Async pipe leak reproducer ==="
  liftIO $ putStrLn "Running 20 commands with parJoin 3"
  liftIO $ putStrLn ""
  liftIO $ ignore $ system "ps -o pid,ppid,comm --no-headers --ppid=$$ 2>/dev/null || echo '(no children)'"
  liftIO $ putStrLn ""
  let cmds =
        [ "echo task-1"
        , "sleep 0.5 && echo task-2"
        , "sleep 0.3 && echo task-3"
        , "echo task-4"
        , "sleep 0.4 && echo task-5"
        , "sleep 0.2 && echo task-6"
        , "echo task-7"
        , "sleep 0.6 && echo task-8"
        , "sleep 0.1 && echo task-9"
        , "echo task-10"
        , "sleep 0.5 && echo task-11"
        , "sleep 0.3 && echo task-12"
        , "echo task-13"
        , "sleep 0.4 && echo task-14"
        , "sleep 0.2 && echo task-15"
        , "echo task-16"
        , "sleep 0.7 && echo task-17"
        , "sleep 0.1 && echo task-18"
        , "echo task-19"
        , "sleep 0.3 && echo task-20"
        ]
  _ <- pull $ runAll cmds
  liftIO $ putStrLn ""
  liftIO $ putStrLn "=== Post-run fd check ==="
  liftIO $ ignore $ system "ls -la /proc/self/fd/ 2>/dev/null | grep pipe || echo '(no pipes)'"
  liftIO $ ignore $ system "ps -o pid,ppid,comm --no-headers --ppid=$$ 2>/dev/null || echo '(no children)'"

module Monitor.Process

import Protocol
import Monitor.Types
import Data.String
import Data.Maybe
import Data.Bits
import Data.Buffer
import Data.C.Array
import Data.C.Ptr
import System.Posix.File.FileDesc
import IO.Async
import IO.Async.Posix
import IO.Async.Util
import System.Posix.File
import System.Posix.Process

%foreign "C:pipe,libc"
prim__pipe : AnyPtr -> PrimIO CInt

%foreign "C:fork,libc"
prim__fork : PrimIO Int

%foreign "C:_exit,libc"
prim__exit : Int -> PrimIO ()

%foreign "C:execvp,libc"
prim__execvp : String -> AnyPtr -> PrimIO Int

%foreign "C:dup2,libc"
prim__dup2 : Int -> Int -> PrimIO Int

%foreign "C:close,libc"
prim__close : Int -> PrimIO Int

%foreign "C:fcntl,libc"
prim__fcntl : Int -> Int -> PrimIO Int

%foreign "C:fcntl,libc"
prim__fcntl_set : Int -> Int -> Int -> PrimIO Int

%foreign "C:open,libc"
prim__open : String -> Int -> PrimIO Int

%foreign "C:cstr_write,cstr_write"
prim__cstr_write : Int -> String -> PrimIO CInt

%foreign "C:cstr_timestamp,cstr_write"
prim__cstr_timestamp : PrimIO String

public export
record ProcInfo where
  constructor MkProcInfo
  name    : String
  fd      : Fd
  pid     : Int
  pending : String
  logPath : Maybe String

export
writeToFd : Int -> String -> IO CInt
writeToFd fd s = primIO $ prim__cstr_write fd s

export
closeLogFd : Maybe Int -> IO ()
closeLogFd Nothing = pure ()
closeLogFd (Just fd) = do
  ignore $ primIO $ prim__close fd
  pure ()

export
writeLogChunk : Maybe Int -> String -> IO ()
writeLogChunk Nothing _ = pure ()
writeLogChunk (Just fd) chunk = do
  _ <- writeToFd fd chunk
  pure ()

export
getCurrentTimeStr : IO String
getCurrentTimeStr = primIO prim__cstr_timestamp

export
writeLogFooter : String -> JobDisplayStatus -> IO ()
writeLogFooter logPath status = do
  ts <- getCurrentTimeStr
  let statusStr := case status of
                      SUCCESS   => "SUCCESS"
                      FAILED    => "FAILED"
                      TIMEDOUT  => "TIMEDOUT"
                      QUEUED    => "QUEUED"
                      RUNNING   => "RUNNING"
                      CANCELLED => "CANCELLED"
  let footer := "[END] " ++ ts ++ " " ++ statusStr ++ "\n"
  _ <- writeToFdAppend logPath footer
  pure ()
  where
    writeToFdAppend : String -> String -> IO CInt
    writeToFdAppend path content = do
      fd <- primIO $ prim__open path 1025
      if fd < 0
        then pure (-1)
        else do
          result <- writeToFd fd content
          ignore $ primIO $ prim__close fd
          pure result

export
openLogFile : Maybe String -> IO (Maybe Int)
openLogFile Nothing = pure Nothing
openLogFile (Just path) = do
  let flags := 544
  fd <- primIO $ prim__open path flags
  if fd < 0
    then pure Nothing
    else do
      header <- getCurrentTimeStr
      let headerLine := "[START] " ++ header ++ "\n"
      _ <- writeToFd fd headerLine
      pure $ Just fd

export
spawnCmd : ProcessTask -> IO (Maybe ProcInfo)
spawnCmd task = do
  let baseCmd = "timeout " ++ show task.timeout ++ "s " ++ task.path ++ " " ++ unwords task.args
  ts <- getCurrentTimeStr
  let (cmd, logPath) = case task.logFile of
                        Nothing => (baseCmd, Nothing)
                        Just lp =>
                          let header := "[START] " ++ ts ++ "\n"
                              wrapped := "{ echo '" ++ header ++ "' > " ++ lp ++ "; " ++
                                         baseCmd ++ " 2>&1 | tee -a " ++ lp ++ "; }"
                          in (wrapped, Just lp)
  pipeArr <- malloc Fd 2
  rc <- primIO $ prim__pipe (unsafeUnwrap pipeArr)
  if rc < 0
    then do
      free pipeArr
      pure Nothing
    else do
      Just buf <- newBuffer 8 | Nothing => do
        free pipeArr
        pure Nothing
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
          argsArr <- fromList [Just "sh", Just "-c", Just cmd, Nothing]
          _ <- primIO $ prim__execvp "/bin/sh" (unsafeUnwrap argsArr)
          free argsArr
          primIO $ prim__exit 127
          pure Nothing
        else do
          _ <- primIO $ prim__close writeFd
          flags <- primIO $ prim__fcntl readFd 3
          _ <- primIO $ prim__fcntl_set readFd 4 (flags .|. 2048)
          pure $ Just $ MkProcInfo task.name (MkFd readBits) childPid "" task.logFile

export
splitOutput : String -> String -> (List String, String)
splitOutput acc new = go (unpack (acc ++ new)) []
  where
    go : List Char -> List String -> (List String, String)
    go [] lines = (reverse lines, "")
    go cs lines =
      let (before, after) = break (== '\n') cs
      in case after of
           [] => (reverse lines, pack before)
           (_ :: rest) => go rest (pack before :: lines)

isDC : Char -> Bool
isDC c = c >= '0' && c <= '9'

natOf : String -> Nat
natOf s = let n = the Integer (cast s) in if n > 0 then fromInteger n else 0

rowColOf : List Char -> (Nat, Nat)
rowColOf cs = case break (== ';') (filter (\c => isDC c || c == ';') cs) of
  (rs, [])        => (max 1 (natOf (pack rs)), 1)
  (rs, _ :: rest) => (max 1 (natOf (pack rs)), max 1 (natOf (pack rest)))

colOf : List Char -> Nat
colOf cs = max 1 (natOf (pack (filter isDC cs)))

isFinal : Char -> Bool
isFinal c = c >= '@' && c <= '~'

mutual
  stripGo : Nat -> Nat -> List Char -> List Char
  stripGo row col [] = []
  stripGo row col ('\x1b' :: '[' :: cs)       = handleCSI row col cs
  stripGo row col ('\x1b' :: ']' :: cs)       = skipOSC row col cs
  stripGo row col ('\x1b' :: '(' :: _ :: cs)  = stripGo row col cs
  stripGo row col ('\x1b' :: ')' :: _ :: cs)  = stripGo row col cs
  stripGo row col ('\x1b' :: '+' :: _ :: cs)  = stripGo row col cs
  stripGo row col ('\x1b' :: '*' :: _ :: cs)  = stripGo row col cs
  stripGo row col ('\x1b' :: _ :: cs)         = stripGo row col cs
  stripGo row col ('\r' :: cs)                = stripGo row 1 cs
  stripGo row col ('\n' :: cs)                = '\n' :: stripGo (row + 1) 1 cs
  stripGo row col (c :: cs)                   = c :: stripGo row (col + 1) cs

  handleCSI : Nat -> Nat -> List Char -> List Char
  handleCSI row col cs =
    let (params, rest) = span (not . isFinal) cs
    in case rest of
         (final :: after) =>
           if final == 'H' || final == 'f'
             then let (tRow, tCol) = rowColOf params
                      nl = if tRow /= row then '\n' :: [] else []
                      pad = replicate (minus tCol col) ' '
                  in nl ++ pad ++ stripGo tRow tCol after
             else if final == 'G'
               then let tCol = colOf params
                    in replicate (minus tCol col) ' ' ++ stripGo row tCol after
               else if final == 'd'
                 then let tRow = max 1 (natOf (pack (filter isDC params)))
                          nl = if tRow /= row then '\n' :: [] else []
                      in nl ++ stripGo tRow col after
                 else stripGo row col after
         [] => []

  skipOSC : Nat -> Nat -> List Char -> List Char
  skipOSC row col [] = []
  skipOSC row col ('\x07' :: cs) = stripGo row col cs
  skipOSC row col ('\x1b' :: '\\' :: cs) = stripGo row col cs
  skipOSC row col (_ :: cs) = skipOSC row col cs

export
stripAnsi : String -> String
stripAnsi s = pack $ stripGo 1 1 (unpack s)

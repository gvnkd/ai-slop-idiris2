module Worker

import System
import System.File -- Для fEOF, fGetLine
import System.File.Process
import System.Concurrency
import Data.String
import public Protocol

public export
data Result = Success String String | Failure String String

public export
data Task : Type where
     Job : {n : Nat} -> (1 _ : Ticket Ready n) -> Task
     Die : Task

-- Вспомогательная функция записи лога
writeLog : Maybe String -> String -> String -> IO ()
writeLog Nothing _ _ = pure () -- Если путь не указан, ничего не делаем
writeLog (Just path) name content = do
  let header = "=== Log for \{name} ===\n"
  res <- writeFile path (header ++ content)
  case res of
    Left err => putStrLn "Worker Error: Could not write log to \{path}: \{show err}"
    Right _  => pure ()

-- Рекурсивное чтение всех строк
readAll : File -> IO String
readAll f = do
  eof <- fEOF f
  if eof
     then pure ""
     else do
       Right line <- fGetLine f | Left err => pure "Error reading line"
       rest <- readAll f
       pure (line ++ rest)

-- Запуск с захватом вывода
runCmdCapture : ProcessTask -> IO (Int, String)
runCmdCapture (MKProcessTask _ path args timeout _ _ _) = do
  let cmd = "timeout " ++ show timeout ++ "s " ++ path ++ " " ++ unwords args ++ " 2>&1"

  -- Распаковываем Either, возвращаемый popen
  res <- popen cmd Read
  case res of
    Left err => pure (1, "Failed to popen: \{show err}")
    Right f => do
      output <- readAll f
      exitCode <- pclose f
      pure (exitCode, output)

handleJob : Int -> (n : Nat) -> (1 t : Ticket Ready n) -> Channel Result -> IO ()
handleJob id Z (MkTicket t) outChan =
  channelPut outChan (Failure t.name "Max retries reached")
handleJob id (S k) t outChan = do
  let (MkTicket task) = t
  putStrLn "Worker \{show id}: Executing \{task.name}..."

  (exitCode, output) <- runCmdCapture task
  -- Пишем лог сразу после получения вывода
  writeLog task.logFile task.name output

  let t_back = MkTicket task {st=InProgress}
  case analyzeResult t_back exitCode of
    Right (msg, _) =>
      channelPut outChan (Success task.name output)
    Left t_failed =>
      if exitCode == 124
         then do
           putStrLn "Worker \{show id}: \{task.name} timed out!"
           handleJob id k (retryTicket t_failed) outChan
         else do
           putStrLn "Worker \{show id}: \{task.name} failed with code \{show exitCode}"
           handleJob id k (retryTicket t_failed) outChan

export
worker : (id : Int) -> Channel Task -> Channel Result -> IO ()
worker id inChan outChan = do
  msg <- channelGet inChan
  case msg of
    Job {n} t => do
      handleJob id n t outChan
      worker id inChan outChan
    Die => pure ()

module Worker

import Data.String
import System
import System.File.Process
import System.Concurrency
import public Protocol

public export
data Result = Success String String | Failure String String

public export
data Task : Type where
     Job : {n : Nat} -> (1 _ : Ticket Ready n) -> Task
     Die : Task

-- Формирует строку команды с использованием системного timeout
runCmd : ProcessTask -> IO Int
runCmd (MKProcessTask _ path args timeout) = do
  -- Собираем команду: timeout Xs path arg1 arg2...
  let fullCmd = "timeout " ++ show timeout ++ "s " ++ path ++ " " ++ unwords args
  system fullCmd

handleJob : Int -> (n : Nat) -> (1 t : Ticket Ready n) -> Channel Result -> IO ()
handleJob id Z (MkTicket t) outChan = 
  channelPut outChan (Failure t.name "Max retries reached")
handleJob id (S k) t outChan = do
  let (MkTicket task) = t -- Временная распаковка для доступа к данным
  putStrLn "Worker \{show id}: Executing \{task.name}..."
  
  exitCode <- runCmd task
  
  -- Возвращаем тикет в систему типов для соблюдения протокола
  let 1 t_back = MkTicket task {st=InProgress}
  case analyzeResult t_back exitCode of
    Left (msg, _) => 
      channelPut outChan (Success task.name msg)
    Right t_failed => 
      if exitCode == 124 -- Специальный код timeout
         then do
           putStrLn "Worker \{show id}: \{task.name} timed out!"
           handleJob id k (retryTicket t_failed) outChan
         else do
           putStrLn "Worker \{show id}: \{task.name} failed with code \{show exitCode}"
           handleJob id k (retryTicket t_failed) outChan
  where
    retryTicket : (1 t : Ticket Failed (S n)) -> Ticket Ready n
    retryTicket (MkTicket t) = MkTicket t

export
worker : (id : Int) -> Channel Task -> Channel Result -> IO ()
worker id inChan outChan = do
  msg <- channelGet inChan
  case msg of
    Job {n} t => do
      handleJob id n t outChan
      worker id inChan outChan
    Die => pure ()

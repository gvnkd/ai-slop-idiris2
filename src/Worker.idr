module Worker

import System.Concurrency
import public Protocol

public export
data Result = Res Int | Failure Int

public export
data Task : Type where
     Job : {n : Nat} -> (1 _ : Ticket Ready n) -> Task
     Die : Task

-- Используем линейную стрелку -@.
-- Она говорит: "этот аргумент (t) будет потреблен ровно один раз".
handleJob : (id : Int) -> (n : Nat) -> (1 t : Ticket Ready n) -> (outChan : Channel Result) -> IO ()
handleJob id Z t outChan = do
  let (MkTicket v) = t
  channelPut outChan (Failure v)
handleJob id (S k) t outChan =
  case processProtocol t of
    OK val => channelPut outChan (Res val)
    Recoverable t_ready => do
      putStrLn "Worker \{show id}: retrying..."
      handleJob id k t_ready outChan -- Линейная передача в рекурсию
    Abandoned val => channelPut outChan (Failure val)

export
worker : (id : Int) -> Channel Task -> Channel Result -> IO ()
worker id inChan outChan = do
  msg <- channelGet inChan
  case msg of
    Job {n} t => do
      -- Теперь Idris увидит, что handleJob официально принимает 1 t
      handleJob id n t outChan
      worker id inChan outChan
    Die => pure ()

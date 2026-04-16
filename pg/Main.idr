module Main

import Control.Linear.LIO
import System.Concurrency
import Data.List

-- 1. Состояния задачи
data TaskState = Ready | InProgress | Done | Failed

-- 2. Ресурс Ticket (GADT)
data Ticket : TaskState -> Nat -> Type where
     MkTicket : (val : Int) -> Ticket st n

-- 3. Сообщения для воркера (GADT)
data Task : Type where
     -- Теперь задача несет в себе тикет с n попытками
     Job : {n : Nat} -> (1 _ : Ticket Ready n) -> Task
     Die : Task

data Result = Res Int | Failure Int

-- Результат выполнения протокола
data StepResult : Nat -> Type where
     OK : Int -> IO () -> StepResult n
     -- Recoverable возможен только если n > 0 (т.е. S k)
     Recoverable : Ticket Ready k -> StepResult (S k)
     Abandoned : Int -> IO () -> StepResult n

startTask : {n : Nat} -> (1 t : Ticket Ready n) -> Ticket InProgress n
startTask (MkTicket v) = MkTicket v

completeTask : {n : Nat} -> (1 t : Ticket InProgress n) -> Either (Int, Ticket Done n) (Ticket Failed n)
completeTask (MkTicket v) =
  if (mod v 10) == 0
     then Right (MkTicket v)
     else Left (v * v, MkTicket v)

-- Retry — единственное место, где n уменьшается!
-- Мы принимаем (S n) и возвращаем n.
retryTicket : (1 t : Ticket Failed (S n)) -> Ticket Ready n
retryTicket (MkTicket v) = MkTicket v

deleteTicket : {n : Nat} -> (1 t : Ticket Done n) -> IO ()
deleteTicket (MkTicket _) = pure ()

discardFailed : {n : Nat} -> (1 t : Ticket Failed n) -> IO ()
discardFailed (MkTicket _) = putStrLn "Задача окончательно провалена"

-- Добавим возможность удалить тикет в состоянии Ready (например, при истечении газа)
cancelReady : {n : Nat} -> (1 _ : Ticket Ready n) -> IO ()
cancelReady (MkTicket _) = putStrLn $ "Газ кончился, тикет отменен"


-- Заметьте сигнатуру: (S n) означает, что нам нужен хотя бы 1 газ для попытки
processProtocol : {n : Nat} -> (1 t : Ticket Ready (S n)) -> StepResult (S n)
processProtocol t =
  let t2 = startTask t in
  case completeTask t2 of
    Left (val, t3) => OK val (deleteTicket t3)
    Right t_err =>
      let (MkTicket v) = t_err in
      if v > 100
         then Abandoned v (discardFailed t_err)
         else Recoverable (retryTicket t_err)

-- Здесь n — это количество попыток
handleJob : Int -> (n : Nat) -> (1 t : Ticket Ready n) -> Channel Result -> IO ()
handleJob id Z t outChan = do
  case t of
    (MkTicket v) => do
      putStrLn "Газ кончился для \{show v}"
      channelPut outChan (Failure 0)

handleJob id (S k) t outChan =
  case processProtocol t of
    OK val cleanup => do
      cleanup
      channelPut outChan (Res val)
    Recoverable t_ready => do
      putStrLn "Retry..."
      handleJob id k t_ready outChan
    Abandoned val cleanup => do
      cleanup
      channelPut outChan (Failure val)


worker : (id : Int) -> Channel Task -> Channel Result -> IO ()
worker id inChan outChan = do
  msg <- channelGet inChan
  case msg of
    Job {n} t => do -- Извлекаем n из Job
--      let 1 t = t
      handleJob id n t outChan
      worker id inChan outChan
    Die => pure ()

main : IO ()
main = do
  putStrLn "Protocol-based Pool Started"
  tasks <- the (IO (Channel Task)) makeChannel
  results <- the (IO (Channel Result)) makeChannel

  -- Используем traverse_ чтобы получить IO (), а не IO (List ThreadID)
  ignore $ fork $ traverse_ (\i => fork (worker i tasks results)) [1..3]

  -- Раздача задач
  let jobs = [1..10]
  -- Указываем, что у каждой задачи будет 3 попытки
  ignore $ fork $ traverse_ (\j => channelPut tasks (Job (MkTicket j {n=3}))) jobs


  -- Сбор результатов
  -- Явно указываем тип лямбды, чтобы Idris понял: мы в IO
  traverse_ (\_ => (the (IO ()) $ do
      resMsg <- channelGet results
      case resMsg of
           Res val => putStrLn "Успех: \{show val}"
           Failure val => putStrLn "Провал: \{show val}"
    )) jobs

  -- Закрытие
  ignore $ fork $ traverse_ (\_ => channelPut tasks Die) jobs
  putStrLn "All tasks processed safely."

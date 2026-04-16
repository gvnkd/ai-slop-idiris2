module Main

import System.Concurrency
import Data.List

-- 1. Состояния задачи
data TaskState = Ready | InProgress | Done

-- 2. Ресурс Ticket (GADT)
data Ticket : TaskState -> Type where
     MkTicket : (val : Int) -> Ticket st

-- 3. Сообщения для воркера (GADT)
-- Теперь Idris четко видит линейность в конструкторе Job
data Task : Type where
     Job : (1 _ : Ticket Ready) -> Task
     Die : Task

data Result = Res Int

-- 4. Протокол переходов
startTask : (1 t : Ticket Ready) -> Ticket InProgress
startTask (MkTicket v) = MkTicket v

completeTask : (1 t : Ticket InProgress) -> (Int, Ticket Done)
completeTask (MkTicket v) = (v * v, MkTicket v)

deleteTicket : (1 t : Ticket Done) -> IO ()
deleteTicket (MkTicket _) = pure ()

-- 5. Логика обработки (Чистая функция-протокол)
-- Гарантирует: Ready -> InProgress -> Done -> Delete
processProtocol : (1 t : Ticket Ready) -> (Int, IO ())
processProtocol t = 
    let t2 = startTask t
        (val, t3) = completeTask t2
    in (val, deleteTicket t3)

-- 6. Воркер
worker : (id : Int) -> Channel Task -> Channel Result -> IO ()
worker id inChan outChan = do
  msg <- channelGet inChan
  case msg of
    Job t => do
      -- Здесь t имеет вес 1
      let 1 t = t
      let (res, cleanup) = processProtocol t
          --(res', cleanup') = processProtocol t  -- Second task execution will fail
      cleanup
      channelPut outChan (Res res)
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
  ignore $ fork $ traverse_ (\j => channelPut tasks (Job (MkTicket j))) jobs

  -- Сбор результатов
  traverse_ (\_ => do
    Res res <- channelGet results
    putStrLn "Result: \{show res}") jobs

  -- Закрытие
  channelPut tasks Die
  channelPut tasks Die
  channelPut tasks Die
  putStrLn "All tasks processed safely."

module Main

import System.Concurrency
import Data.List

-- 1. Линейный ресурс
record Ticket where
  constructor MKTicket
  1 val : Int

-- 2. В конструкторе Job обязательно называем аргумент, например 't'
data Task : Type where
     Job : (1 ticket : Ticket) -> Task
     Die : Task

data Result = Done Int Int

-- 3. Чистая функция с жесткой проверкой линейности
processJob : (1 _ : Ticket) -> Int
processJob (MKTicket val) = val -- Работает, так как val потреблен 1 раз

-- 4. Воркер-процесс
worker : (id : Int) -> Channel Task -> Channel Result -> IO ()
worker id inChan outChan = do
  msg <- channelGet inChan
  case msg of
    Job t => do
      let res = processJob t 
      channelPut outChan (Done id res)
      worker id inChan outChan
    Die => pure ()

spawnPool : Int -> Channel Task -> Channel Result -> IO (List ThreadID)
spawnPool n inChan outChan = 
  traverse (\i => fork (worker i inChan outChan)) [1..n]

main : IO ()
main = do
  putStrLn "Starting Linear Worker Pool..."
  tasks <- the (IO (Channel Task)) makeChannel
  results <- the (IO (Channel Result)) makeChannel
  
  workerThreads <- spawnPool 3 tasks results
  
  let jobs = [1..6]
  
  -- Отправляем задачи асинхронно
  ignore $ fork $ traverse_ (\j => channelPut tasks (Job (MKTicket j))) jobs

  -- Собираем результаты
  traverse_ (\_ => do
    Done wId res <- channelGet results
    putStrLn "Воркер \{show wId} вернул результат: \{show res}"
    ) jobs
  
  -- Завершаем воркеров
  traverse_ (\_ => channelPut tasks Die) workerThreads
  putStrLn "Готово. Все ресурсы корректно потреблены."

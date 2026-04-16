module Main

import System.Concurrency
import Data.List
import Worker

-- Утилита для запуска пула
spawnPool : Int -> Channel Task -> Channel Result -> IO ()
spawnPool count tasks results = 
  ignore $ fork $ traverse_ (\i => fork (worker i tasks results)) [1..count]

main : IO ()
main = do
  putStrLn "Starting Refactored Worker Pool"
  
  tasks <- the (IO (Channel Task)) makeChannel
  results <- the (IO (Channel Result)) makeChannel
  
  -- 1. Инициализация инфраструктуры
  spawnPool 3 tasks results
  
  -- 2. Отправка задач (бизнес-логика)
  let jobs = [1..10]
  ignore $ fork $ traverse_ (\j => channelPut tasks (Job (MkTicket j {n=3}))) jobs

  -- 3. Сбор результатов
  traverse_ (\_ => (the (IO ()) $ do
      resMsg <- channelGet results
      case resMsg of
           Res val => putStrLn "Success: \{show val}"
           Failure val => putStrLn "Final Failure: \{show val}"
    )) jobs
  
  -- 4. Завершение работы
  traverse_ (\_ => channelPut tasks Die) [1..3]
  putStrLn "Done."

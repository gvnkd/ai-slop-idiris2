module Main

import System
import System.File
import System.Concurrency
import Data.List
import Worker
import Protocol
import Monitor.Provider

spawnPool : Int -> Channel Task -> Channel Result -> IO ()
spawnPool count tasks results = 
  ignore $ fork $ traverse_ (\i => fork (worker i tasks results)) [1..count]

main : IO ()
main = do
  ignore $ system "mkdir -p logs"
  putStrLn "=== Linux Process Worker Pool (Auto-JSON) ==="

  -- 1. Пытаемся загрузить конфиг
  Just (_, tasksFromConfig) <- Monitor.Provider.loadTasks "tasks.json"
    | Nothing => putStrLn "Shutting down due to config error."

  
  tasks <- the (IO (Channel Task)) makeChannel
  results <- the (IO (Channel Result)) makeChannel
  
  spawnPool 2 tasks results
  
  ignore $ fork $ traverse_ (\j => channelPut tasks (Job (MkTicket j {n=2}))) tasksFromConfig

  -- Сбор ответов
  traverse_ (\_ => (the (IO ()) $ do
      resMsg <- channelGet results
      case resMsg of
           Success name out => do
             putStrLn "[OK] \{name}"
             putStrLn "--- Output ---"
             putStrLn out
             putStrLn "--------------"
           Failure name err => putStrLn "[FAIL] \{name}: \{err}"
      )) [1..4]
  
  traverse_ (\_ => channelPut tasks Die) [1..2]
  putStrLn "All processes handled."

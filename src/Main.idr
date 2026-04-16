module Main

import System.Concurrency
import Data.List
import Worker

spawnPool : Int -> Channel Task -> Channel Result -> IO ()
spawnPool count tasks results = 
  ignore $ fork $ traverse_ (\i => fork (worker i tasks results)) [1..count]

main : IO ()
main = do
  putStrLn "=== Linux Process Worker Pool ==="
  
  tasks <- the (IO (Channel Task)) makeChannel
  results <- the (IO (Channel Result)) makeChannel
  
  spawnPool 2 tasks results
  
  -- Список реальных задач
  let jobs = [
        MKProcessTask "List files" "/run/current-system/sw/bin/eza" ["-la", "/"] 2,
        MKProcessTask "Fast sleep" "sleep" ["0.5"] 2,
        MKProcessTask "Long sleep (Timeout Test)" "sleep" ["5"] 1,
        MKProcessTask "Invalid binary" "/usr/bin/not-exist" [] 1
      ]
  
  ignore $ fork $ traverse_ (\j => channelPut tasks (Job (MkTicket j {n=2}))) jobs

  -- Сбор ответов
  traverse_ (\_ => (the (IO ()) $ do
      resMsg <- channelGet results
      case resMsg of
           Success name out => putStrLn "[OK] \{name}: \{out}"
           Failure name err => putStrLn "[FAIL] \{name}: \{err}"
    )) [1..4]
  
  traverse_ (\_ => channelPut tasks Die) [1..2]
  putStrLn "All processes handled."

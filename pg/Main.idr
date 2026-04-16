module Main

import Data.Buffer
import Data.IORef
import System
import System.File
import System.File.Buffer
import System.File.Process
import System.Concurrency

record JobDesc where
  constructor MkJobDesc
  jobName : String
  running : IORef Bool
  process : SubProcess

data Task = Job Int | Die
data Result = Done Int Int


worker : (id : Int) -> Channel Task -> Channel Result -> IO ()
worker id inChan outChan = do
    msg <- channelGet inChan -- Теперь получаем 'Task' напрямую
    case msg of
        Job val => do
            let res = val * val
            channelPut outChan (Done id res)
            worker id inChan outChan
        Die =>
            pure ()

spawnPool : Int -> Channel Task -> Channel Result -> IO (List ThreadID)
spawnPool n inChan outChan =
    traverse (\i => fork (worker i inChan outChan)) [1..n]

-- Функция для фонового чтения
readerLoop : File -> Buffer -> IO ()
readerLoop f buf = do
  Right outString <- fGetLine f
    | Left err => putStrLn $ "Cannot get next line: " ++ show err
  putStr outString
  readerLoop f buf
  putStrLn "reader Done"

spawn : IO ()
spawn = do
  putStrLn "Starting spawned process"
  --Right sp1 <- popen2 "tail -F /tmp/idris_log_System_Check.log"
  Right sp1 <- popen2 "molecule test"
    | Left err => putStrLn $ "Cannot spawn process: " ++ show err

  putStrLn "tail -F spawned"
  Just buf <- newBuffer 1024
    | Nothing => putStrLn "Cannot create a buffer"

  putStrLn "Starting reader loop"
  readerLoop sp1.output buf
  pid <- popen2Wait sp1
  putStrLn "Done"

main : IO ()
main = do
  putStrLn "Starting"
  -- Создаем каналы
  tasks : Channel Task <- makeChannel
  results : Channel Result <- makeChannel
  
  -- 1. Запускаем пул из 3-х воркеров
  workerThreads <- spawnPool 3 tasks results
  
  -- 2. Раздаем задачи (например, 5 штук)
  let jobs = [1..10]
  _ <- fork $ traverse_ (\j => channelPut tasks (Job j)) jobs
  
  -- 3. Собираем результаты
  traverse_ (\_ => do
      Done wId res <- channelGet results
      putStrLn "Воркер \{show wId} вернул: \{show res}"
    ) jobs
  
  -- 4. Рассылаем сигнал завершения всем воркерам
  traverse_ (\_ => channelPut tasks Die) workerThreads
  
  putStrLn "Все задачи выполнены."
  {--
  _ <- fork spawn
  putStrLn "Main thread is free! Typing something every 2 seconds..."

  let mainLoop : IO ()
      mainLoop = do
        putStrLn "--- Main thread tick ---"
        usleep 30000000
        mainLoop

  mainLoop
  --}

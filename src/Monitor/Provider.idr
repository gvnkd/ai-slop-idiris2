module Monitor.Provider

import Protocol
import Monitor.Types
import System.File
import Language.JSON
import JSON

public export
loadTasks : String -> IO (Maybe (List ProcessTask))
loadTasks filename = do
  res <- readFile filename
  case res of
    Left err => do
      putStrLn "Error: Config file '\{filename}' not found (\{show err})"
      pure Nothing
    Right content =>
      case decode {a = List ProcessTask} content of
        Right tasks => pure (Just tasks)
        Left err    => do
          putStrLn "Error: Failed to parse JSON in '\{filename}': \{err}"
          pure Nothing

public export
toJobEntries : List ProcessTask -> List JobEntry
toJobEntries = map (\t => MkJobEntry t QUEUED)

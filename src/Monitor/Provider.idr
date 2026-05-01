module Monitor.Provider

import Protocol
import Monitor.Types
import System.File
import Language.JSON
import Data.List

getString : List (String, JSON) -> String -> Either String String
getString pairs key =
  case lookup key pairs of
    Just (JString s) => Right s
    _               => Left "Missing or invalid string field: \{key}"

getStrings : List (String, JSON) -> String -> Either String (List String)
getStrings pairs key =
  case lookup key pairs of
    Just (JArray arr) => traverse extractString arr
    _                => Right []
  where
    extractString : JSON -> Either String String
    extractString (JString s) = Right s
    extractString _          = Left "Expected string in array"

getInt : List (String, JSON) -> String -> Either String Int
getInt pairs key =
  case lookup key pairs of
    Just (JNumber n) => Right (cast n)
    _               => Left "Missing or invalid number field: \{key}"

getMaybeString : List (String, JSON) -> String -> Maybe String
getMaybeString pairs key =
  case lookup key pairs of
    Just (JString s) => Just s
    _               => Nothing

getMaybeBool : List (String, JSON) -> String -> Maybe Bool
getMaybeBool pairs key =
  case lookup key pairs of
    Just (JBoolean b) => Just b
    _                => Nothing

getEnvVarsFromJSON : List (String, JSON) -> String -> List (String, String)
getEnvVarsFromJSON pairs key =
  case lookup key pairs of
    Just (JObject envPairs) => map (\(k, v) => (k, extract v)) envPairs
    _                      => []
  where
    extract : JSON -> String
    extract (JString s) = s
    extract _          = ""

parseJobParams : List (String, JSON) -> String -> Maybe String -> Either String ProcessTask
parseJobParams pairs name batchName =
  do
    path       <- getString pairs "path"
    args       <- getStrings pairs "args"
    timeout    <- getInt pairs "timeout"
    let logFile    = getMaybeString pairs "logFile"
    let blockingIO = getMaybeBool pairs "blockingIO"
    let envVars    = getEnvVarsFromJSON pairs "envVars"
    pure $ MKProcessTask name batchName path args timeout logFile blockingIO envVars

parseBatch : String -> List (String, JSON) -> Either String (List ProcessTask)
parseBatch batchName jobPairs =
  traverse (\(jobName, jobJSON) =>
    case jobJSON of
      JObject pairs => parseJobParams pairs jobName (Just batchName)
      _            => Left "Job '\{jobName}' must be an object") jobPairs

parseTaskConfig : List (String, JSON) -> TaskConfig
parseTaskConfig pairs =
  MkTaskConfig (getMaybeString pairs "batchName")
               (getMaybeNat pairs "maxWorkers")
               (getMaybeNat pairs "leftWidth")
  where
    getMaybeNat : List (String, JSON) -> String -> Maybe Nat
    getMaybeNat ps k =
      case lookup k ps of
        Just (JNumber n) => Just (cast {to = Nat} n)
        _               => Nothing

parseTaskFile : JSON -> Either String (TaskConfig, List ProcessTask)
parseTaskFile (JObject topPairs) =
  let config = case lookup "config" topPairs of
                 Just (JObject configPairs) => parseTaskConfig configPairs
                 _                          => MkTaskConfig Nothing Nothing Nothing
      batchPairs = filter (\(k, _) => k /= "config") topPairs
  in case traverse (\(batchName, batchJSON) =>
       case batchJSON of
         JObject jobPairs => parseBatch batchName jobPairs
         _               => Left "Batch '\{batchName}' must be an object") batchPairs of
       Left err       => Left err
       Right tasksLists => Right (config, concat tasksLists)
parseTaskFile _ =
  Left "Root must be a JSON object"

public export
covering
loadTasks : String -> IO (Maybe (TaskConfig, List ProcessTask))
loadTasks filename = do
  res <- readFile filename
  case res of
    Left err => do
      putStrLn "Error: Config file '\{filename}' not found (\{show err})"
      pure Nothing
    Right content =>
      case Language.JSON.parse content of
        Nothing => do
          putStrLn "Error: Invalid JSON in '\{filename}'"
          pure Nothing
        Just json =>
          case parseTaskFile json of
            Left err => do
              putStrLn "Error: Failed to parse '\{filename}': \{err}"
              pure Nothing
            Right result => pure (Just result)

public export
toJobEntries : List ProcessTask -> List JobEntry
toJobEntries = map (\t => MkJobEntry t QUEUED)

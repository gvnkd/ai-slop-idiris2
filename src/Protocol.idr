module Protocol

import Language.JSON
import Language.Reflection
import JSON.Derive
import Data.SortedMap

%language ElabReflection

public export
record TaskConfig where
  constructor MkTaskConfig
  batchName  : Maybe String
  maxWorkers : Maybe Nat
  leftWidth  : Maybe Nat

export
FromJSON TaskConfig where
  fromJSON = withObject "TaskConfig" $ \o =>
    [| MkTaskConfig (fieldMaybe o "batchName")
                    (fieldMaybe o "maxWorkers")
                    (fieldMaybe o "leftWidth") |]

public export
record JobParams where
  constructor MkJobParams
  path       : String
  args       : List String
  timeout    : Int
  logFile    : Maybe String
  blockingIO : Maybe Bool
  envVars    : List (String, String)

parseEnvVars : SortedMap String String -> List (String, String)
parseEnvVars = SortedMap.toList

export
FromJSON JobParams where
  fromJSON = withObject "JobParams" $ \o =>
    [| MkJobParams (field      o "path")
                   (field      o "args")
                   (field      o "timeout")
                   (field      o "logFile")
                   (fieldMaybe o "blockingIO")
                   (map parseEnvVars $ fieldWithDeflt o (the (SortedMap String String) SortedMap.empty) "envVars") |]

public export
record ProcessTask where
  constructor MKProcessTask
  name       : String
  batchName  : Maybe String
  path       : String
  args       : List String
  timeout    : Int
  logFile    : Maybe String
  blockingIO : Maybe Bool
  envVars    : List (String, String)

public export
data TaskState = Ready | InProgress | Done | Failed

public export
data Ticket : TaskState -> Nat -> Type where
     MkTicket : (task : ProcessTask) -> Ticket st n

public export
data StepResult : Nat -> Type where
     OK : String -> StepResult n
     Recoverable : Ticket Ready k -> StepResult (S k)
     Abandoned : String -> StepResult n

export
startTask : {n : Nat} -> (1 t : Ticket Ready n) -> Ticket InProgress n
startTask (MkTicket t) = MkTicket t

-- Сама логика "решать, что делать с кодом возврата"
-- Теперь Right — это успех (String, Ticket Done), а Left — ошибка (Ticket Failed)
export
analyzeResult : {n : Nat} -> (1 t : Ticket InProgress n) -> Int -> Either (Ticket Failed n) (String, Ticket Done n)
analyzeResult (MkTicket t) code =
  if code == 0
     then Right ("Success", MkTicket t)
     else Left (MkTicket t)

export
retryTicket : (1 t : Ticket Failed (S n)) -> Ticket Ready n
retryTicket (MkTicket t) = MkTicket t


module Monitor.Types

import public Protocol
import Data.Maybe
import Data.List

public export
data JobDisplayStatus = QUEUED | RUNNING | SUCCESS | FAILED | CANCELLED

public export
Eq JobDisplayStatus where
  QUEUED    == QUEUED    = True
  RUNNING   == RUNNING   = True
  SUCCESS   == SUCCESS   = True
  FAILED    == FAILED    = True
  CANCELLED == CANCELLED = True
  _         == _         = False

public export
Show JobDisplayStatus where
  show QUEUED     = "QUEUED"
  show RUNNING    = "RUNNING"
  show SUCCESS    = "SUCCESS"
  show FAILED     = "FAILED"
  show CANCELLED  = "CANCELLED"

public export
toDisplayStatus : TaskState -> JobDisplayStatus
toDisplayStatus Ready      = QUEUED
toDisplayStatus InProgress = RUNNING
toDisplayStatus Done       = SUCCESS
toDisplayStatus Failed     = FAILED

public export
record LogLine where
  constructor MkLogLine
  stream : String
  text   : String

public export
record JobEntry where
  constructor MkJobEntry
  task   : ProcessTask
  status : JobDisplayStatus

public export
data JobUpdate
  = JobOutput String (List LogLine)
  | JobFinished String JobDisplayStatus
  | AllDone Bool

public export
data CompletionMsg
  = TaskDone String JobDisplayStatus
  | WorkerExit

public export
record JobMonitorState where
  constructor MkJobMonitorState
  jobs         : List JobEntry
  selected     : Nat
  jobLogs      : List (List LogLine)
  logOffset    : Nat
  logColOffset : Nat
  allDone      : Bool
  hasFailed    : Bool

public export
indexNat : Nat -> List a -> Maybe a
indexNat _ []        = Nothing
indexNat 0 (x :: _)  = Just x
indexNat (S n) (_ :: xs) = indexNat n xs

public export
getSelectedJob : JobMonitorState -> Maybe JobEntry
getSelectedJob st = indexNat st.selected st.jobs

public export
getSelectedLogs : JobMonitorState -> List LogLine
getSelectedLogs st = reverse $ fromMaybe [] $ indexNat st.selected st.jobLogs

public export
initialState : List JobEntry -> JobMonitorState
initialState jobs =
  MkJobMonitorState jobs 0 (replicate (length jobs) []) 0 0 False False

updateAtIdx : Nat -> (a -> a) -> List a -> List a
updateAtIdx _ _ [] = []
updateAtIdx 0 f (x :: xs) = f x :: xs
updateAtIdx (S n) f (x :: xs) = x :: updateAtIdx n f xs

findEntryIdx : String -> List JobEntry -> Maybe Nat
findEntryIdx _ [] = Nothing
findEntryIdx name (e :: es) =
  if e.task.name == name then Just 0 else map S (findEntryIdx name es)

public export
updateJobByName : String -> JobDisplayStatus -> List LogLine -> JobMonitorState -> JobMonitorState
updateJobByName name status logs st =
  case findEntryIdx name st.jobs of
    Just idx => { jobs := updateAtIdx idx ({ status := status }) st.jobs
                , jobLogs := updateAtIdx idx (const logs) st.jobLogs
                } st
    Nothing => st

public export
appendJobLogBatch : String -> List LogLine -> JobMonitorState -> JobMonitorState
appendJobLogBatch name lines st =
  case findEntryIdx name st.jobs of
    Just idx => { jobLogs := updateAtIdx idx (\old => lines ++ old) st.jobLogs } st
    Nothing => st

public export
updateJobStatus : String -> JobDisplayStatus -> JobMonitorState -> JobMonitorState
updateJobStatus name status st =
  let failed = status == FAILED || status == CANCELLED
  in case findEntryIdx name st.jobs of
    Just idx => { jobs := updateAtIdx idx ({ status := status }) st.jobs
                , hasFailed := st.hasFailed || failed
                } st
    Nothing => st

public export
setAllDone : JobMonitorState -> JobMonitorState
setAllDone st = { allDone := True } st

public export
findRunningJobName : JobMonitorState -> Maybe String
findRunningJobName st =
  case find (\e => e.status == RUNNING) st.jobs of
    Just e  => Just e.task.name
    Nothing => Nothing

public export
cancelJobByName : String -> JobMonitorState -> JobMonitorState
cancelJobByName name st =
  case findEntryIdx name st.jobs of
    Just idx => { jobs := updateAtIdx idx ({ status := CANCELLED }) st.jobs
                , hasFailed := True
                } st
    Nothing => st

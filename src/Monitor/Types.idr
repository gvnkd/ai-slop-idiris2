module Monitor.Types

import public Protocol
import Data.Maybe
import Data.List

public export
data JobDisplayStatus = QUEUED | RUNNING | SUCCESS | FAILED | TIMEDOUT | CANCELLED

public export
Eq JobDisplayStatus where
  QUEUED    == QUEUED    = True
  RUNNING   == RUNNING   = True
  SUCCESS   == SUCCESS   = True
  FAILED    == FAILED    = True
  TIMEDOUT  == TIMEDOUT  = True
  CANCELLED == CANCELLED = True
  _         == _         = False

public export
Show JobDisplayStatus where
  show QUEUED     = "QUEUED"
  show RUNNING    = "RUNNING"
  show SUCCESS    = "SUCCESS"
  show FAILED     = "FAILED"
  show TIMEDOUT   = "TIMEDOUT"
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
  | JobStarted String Int
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
  jobPids      : List (Maybe Int)
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
  MkJobMonitorState jobs 0 (replicate (length jobs) [])
    (replicate (length jobs) Nothing) 0 0 False False

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
  let failed = status == FAILED || status == TIMEDOUT || status == CANCELLED
  in case findEntryIdx name st.jobs of
    Just idx =>
      case indexNat idx st.jobs of
        Just entry =>
          if entry.status == CANCELLED
            then st
            else { jobs := updateAtIdx idx ({ status := status }) st.jobs
                 , hasFailed := st.hasFailed || failed
                 } st
        Nothing => st
    Nothing => st

public export
setAllDone : JobMonitorState -> JobMonitorState
setAllDone st = { allDone := True } st

public export
setJobStatus : String -> JobDisplayStatus -> JobMonitorState -> JobMonitorState
setJobStatus name status st =
  case findEntryIdx name st.jobs of
    Just idx => { jobs := updateAtIdx idx ({ status := status }) st.jobs } st
    Nothing => st

public export
setJobPid : String -> Int -> JobMonitorState -> JobMonitorState
setJobPid name pid st =
  case findEntryIdx name st.jobs of
    Just idx => { jobPids := updateAtIdx idx (const $ Just pid) st.jobPids } st
    Nothing => st

public export
findSelectedJobName : JobMonitorState -> Maybe String
findSelectedJobName st =
  case indexNat st.selected st.jobs of
    Just e  => if e.status == RUNNING then Just e.task.name else Nothing
    Nothing => Nothing

public export
findRunningJobName : JobMonitorState -> Maybe String
findRunningJobName st =
  case find (\e => e.status == RUNNING) st.jobs of
    Just e  => Just e.task.name
    Nothing => Nothing

public export
cancelJobByName : String -> JobMonitorState -> (JobMonitorState, Maybe Int)
cancelJobByName name st =
  case findEntryIdx name st.jobs of
    Just idx =>
      let pid = case indexNat idx st.jobPids of
                  Just p => p
                  Nothing => Nothing
       in ( { jobs := updateAtIdx idx ({ status := CANCELLED }) st.jobs
            , hasFailed := True
            } st
          , pid )
    Nothing => (st, Nothing)

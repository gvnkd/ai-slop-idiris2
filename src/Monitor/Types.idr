module Monitor.Types

import public Protocol
import Data.Maybe
import Data.List

public export
data JobDisplayStatus = QUEUED | RUNNING | SUCCESS | FAILED

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
data JobUpdate = JobOutput String (List LogLine) | JobFinished String JobDisplayStatus

public export
record JobMonitorState where
  constructor MkJobMonitorState
  jobs         : List JobEntry
  selected     : Nat
  jobLogs      : List (List LogLine)
  logOffset    : Nat
  logColOffset : Nat

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
initialState jobs = MkJobMonitorState jobs 0 (replicate (length jobs) []) 0 0

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
  case findEntryIdx name st.jobs of
    Just idx => { jobs := updateAtIdx idx ({ status := status }) st.jobs } st
    Nothing => st

module Monitor.Handler

import TUI.Event
import TUI.Key
import Data.List.Quantifiers
import Data.List.Quantifiers.Extra
import Monitor.Types
import Monitor.Process
import System.Posix.Signal.Types

%foreign "C:kill,libc"
prim__kill : Int -> Int -> PrimIO Int

public export
onJobUpdate : Event.Handler JobMonitorState () JobUpdate
onJobUpdate (JobOutput name lines) st =
  update $ appendJobLogBatch name lines st
onJobUpdate (JobStarted name pid) st =
  update $ setJobStatus name RUNNING $ setJobPid name pid st
onJobUpdate (JobFinished name status) st =
  update $ updateJobStatus name status st
onJobUpdate (AllDone _) st =
  update $ setAllDone st

public export
covering
onKey : Event.Handler JobMonitorState () Key
onKey Up st =
  let newSel = case st.selected of
                 0   => 0
                 S n => n
  in update $ { selected := newSel, logOffset := 0, logColOffset := 0 } st
onKey Down st =
  let maxIdx = case length st.jobs of
                 0   => 0
                 S n => n
      newSel = min maxIdx (st.selected + 1)
  in update $ { selected := newSel, logOffset := 0, logColOffset := 0 } st
onKey (Alpha 'k') st =
  let newOffset = st.logOffset + 1
  in update $ { logOffset := newOffset } st
onKey (Alpha 'j') st =
  let newOffset = case st.logOffset of
                    0   => 0
                    S n => n
  in update $ { logOffset := newOffset } st
onKey (Alpha 'l') st =
  let newOffset = st.logColOffset + 4
  in update $ { logOffset := newOffset } st
onKey (Alpha 'h') st =
  let newOffset = case st.logColOffset of
                    0   => 0
                    S n => n `minus` 4
  in update $ { logColOffset := newOffset } st
onKey (Alpha 'x') st =
  case findSelectedJobName st of
    Just name =>
      let (newSt, mPid) = cancelJobByName name st
      in case mPid of
           Just pid => do
             ignore $ primIO $ prim__kill pid 15
             ts <- getCurrentTimeStr
             update $ appendJobLogBatch name [MkLogLine "" "\{ts} CANCELLED"] newSt
           Nothing => update newSt
    Nothing   => ignore
onKey (Alpha 'q') _ = exit
onKey Escape      _ = exit
onKey _           st = ignore

public export
handler : Event.Handler JobMonitorState () (HSum [JobUpdate, Key])
handler = union [onJobUpdate, onKey]

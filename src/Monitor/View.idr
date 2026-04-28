module Monitor.View

import TUI.View
import TUI.Painting
import TUI.Geometry
import TUI.Layout
import Monitor.Types
import Protocol
import Data.List

View JobDisplayStatus where
  size _ = MkArea 3 1
  paint _ window QUEUED = do
    showTextAt window.nw "[Q]"
  paint _ window RUNNING = do
    showTextAt window.nw "[R]"
  paint _ window SUCCESS = do
    showTextAt window.nw "[+]"
  paint _ window FAILED = do
    showTextAt window.nw "[x]"
  paint _ window CANCELLED = do
    showTextAt window.nw "[X]"

View JobEntry where
  size entry = MkArea (4 + length entry.task.name) 1
  paint state window entry = do
    let (badgeRect, rest) = window.splitLeft 3
    paint Normal badgeRect entry.status
    case state of
      Focused => sgr [SetReversed True]
      _       => sgr []
    showTextAt rest.nw $ " " ++ entry.task.name
    sgr [Reset]

View LogLine where
  size line = MkArea (length line.stream + 1 + length line.text) 1
  paint _ window line = do
    showTextAt window.nw line.stream
    showTextAt (window.nw.shiftRight (the Integer $ cast $ length line.stream)) line.text

covering
paintJobList : Rect -> List JobEntry -> Nat -> Nat -> Context ()
paintJobList _ [] _ _ = pure ()
paintJobList window (entry :: entries) selectedIdx currentIdx =
  if window.height == 0
    then pure ()
    else do
      let st = if currentIdx == selectedIdx then Focused else Normal
      remaining <- packTop st window entry
      paintJobList remaining entries selectedIdx (currentIdx + 1)

covering
paintLogLines : Rect -> Nat -> List LogLine -> Context ()
paintLogLines _ _ [] = pure ()
paintLogLines window colOffset (line :: rest) =
  if window.height == 0
    then pure ()
    else do
      let prefW = length line.stream + 1
      let maxW = minus window.width prefW
      let chars = drop colOffset (unpack line.text)
      let trimmed = MkLogLine line.stream (pack (take maxW chars))
      remaining <- packTop Normal window trimmed
      paintLogLines remaining colOffset rest

autoScrollOffset : Nat -> Nat -> List LogLine -> Nat
autoScrollOffset viewH scrollUp logs = minus (length logs) viewH `minus` scrollUp

export covering
View JobMonitorState where
  size _ = MkArea 80 24
  paint state window st = do
    Box.fill ' ' window
    Box.border window
    let inner = shrink window
    let (titleRect, body) = inner.splitTop 1
    showTextAt titleRect.nw "Job Monitor"
    body <- packTop Normal body HRule
    let (content, legendArea) = body.splitBottom 2
    legendArea <- packTop Normal legendArea HRule
    let (legendText, statusArea) = legendArea.splitLeft 40
    showTextAt legendText.nw
      "\x2191\x2193:jobs  j/k:vscroll  h/l:hscroll  x:cancel  q:quit"
    case (st.allDone, st.hasFailed) of
      (True, False) => do
        sgr [SetForeground Green]
        showTextAt statusArea.nw "ALL JOBS DONE"
        sgr [Reset]
      (True, True) => do
        sgr [SetForeground Yellow]
        showTextAt statusArea.nw "ALL JOBS DONE"
        sgr [Reset]
      _ => pure ()
    let leftWidth = max 10 (integerToNat (natToInteger content.width * 3 `div` 10))
    let (left, mid) = content.splitLeft leftWidth
    let (sep, right) = mid.splitLeft 1
    case st.jobs of
      [] => do
        showTextAt left.nw "No jobs available"
      _  => paintJobList left st.jobs st.selected 0
    paint Normal sep VRule
    let logs = getSelectedLogs st
    case logs of
      [] => do
        showTextAt right.nw "No log output"
      _  => paintLogLines right st.logColOffset (drop (autoScrollOffset right.height st.logOffset logs) logs)
    sgr [Reset]

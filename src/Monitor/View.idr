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
    sgr [SetForeground Yellow, SetBackground Blue]
    showTextAt window.nw "[Q]"
    sgr [Reset, SetBackground Blue]
  paint _ window RUNNING = do
    sgr [SetForeground Cyan, SetBackground Blue]
    showTextAt window.nw "[R]"
    sgr [Reset, SetBackground Blue]
  paint _ window SUCCESS = do
    sgr [SetForeground Green, SetBackground Blue]
    showTextAt window.nw "[+]"
    sgr [Reset, SetBackground Blue]
  paint _ window FAILED = do
    sgr [SetForeground Red, SetBackground Blue]
    showTextAt window.nw "[x]"
    sgr [Reset, SetBackground Blue]

View JobEntry where
  size entry = MkArea (4 + length entry.task.name) 1
  paint state window entry = do
    let (badgeRect, rest) = window.splitLeft 3
    paint Normal badgeRect entry.status
    case state of
      Focused => sgr [SetReversed True, SetBackground Blue]
      _ => sgr [SetForeground White, SetBackground Blue]
    showTextAt rest.nw $ " " ++ entry.task.name
    sgr [Reset, SetBackground Blue]

View LogLine where
  size line = MkArea (length line.stream + 1 + length line.text) 1
  paint _ window line = do
    let prefixColor = if line.stream == "stdout>" then Cyan else Magenta
    sgr [SetForeground prefixColor, SetBackground Blue]
    showTextAt window.nw line.stream
    sgr [Reset, SetBackground Blue]
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

export covering
View JobMonitorState where
  size _ = MkArea 80 24
  paint state window st = do
    sgr [SetBackground Blue]
    Box.fill ' ' window
    sgr [SetForeground White, SetBackground Blue]
    Box.border window
    let inner = shrink window
    let (titleRect, body) = inner.splitTop 1
    sgr [SetForeground White, SetBackground Blue]
    showTextAt titleRect.nw "Job Monitor"
    sgr [SetForeground White, SetBackground Blue]
    body <- packTop Normal body HRule
    let (content, legendArea) = body.splitBottom 2
    sgr [SetForeground White, SetBackground Blue]
    legendArea <- packTop Normal legendArea HRule
    let leftWidth = max 10 (integerToNat (natToInteger content.width * 3 `div` 10))
    let (left, mid) = content.splitLeft leftWidth
    let (sep, right) = mid.splitLeft 1
    case st.jobs of
      [] => do
        sgr [SetForeground White, SetBackground Blue]
        showTextAt left.nw "No jobs available"
      _  => paintJobList left st.jobs st.selected 0
    sgr [SetForeground White, SetBackground Blue]
    paint Normal sep VRule
    let logs = getSelectedLogs st
    case logs of
      [] => do
        sgr [SetForeground White, SetBackground Blue]
        showTextAt right.nw "No log output"
      _  => paintLogLines right st.logColOffset (drop st.logOffset logs)
    sgr [SetForeground White, SetBackground Blue]
    showTextAt legendArea.nw "↑↓:jobs  j/k:vscroll  h/l:hscroll  q:quit"
    sgr [Reset]

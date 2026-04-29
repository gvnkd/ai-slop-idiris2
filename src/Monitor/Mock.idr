module Monitor.Mock

import Monitor.Types
import Protocol

public export
loadMockJobs : IO (List JobEntry)
loadMockJobs = pure [
    MkJobEntry (MKProcessTask "List Root Directory" "ls" ["-la", "./"] 2 (Just "logs/root_dir.log") Nothing []) SUCCESS
  , MkJobEntry (MKProcessTask "Quick Sleep" "sleep" ["0.5"] 1 (Just "logs/timeout_error.log") Nothing []) SUCCESS
  , MkJobEntry (MKProcessTask "Timed Out Task" "sleep" ["5"] 1 Nothing Nothing []) TIMEDOUT
  , MkJobEntry (MKProcessTask "Missing Binary Test" "/usr/bin/not-exist" [] 5 Nothing Nothing []) QUEUED
  , MkJobEntry (MKProcessTask "Health Check" "echo" ["OK"] 1 Nothing Nothing []) RUNNING
  , MkJobEntry (MKProcessTask "Very Long Job Name That Exceeds Column Width" "true" [] 1 Nothing Nothing []) QUEUED
  ]

successLogs : String -> List LogLine
successLogs name = [
    MkLogLine "stdout>" "Starting task: \{name}"
  , MkLogLine "stdout>" "Working..."
  , MkLogLine "stdout>" "Processing item 1 of 10"
  , MkLogLine "stdout>" "Processing item 2 of 10"
  , MkLogLine "stdout>" "Processing item 3 of 10"
  , MkLogLine "stdout>" "Processing item 4 of 10"
  , MkLogLine "stdout>" "Processing item 5 of 10"
  , MkLogLine "stdout>" "Processing item 6 of 10"
  , MkLogLine "stdout>" "Processing item 7 of 10"
  , MkLogLine "stdout>" "Processing item 8 of 10"
  , MkLogLine "stdout>" "Processing item 9 of 10"
  , MkLogLine "stdout>" "Processing item 10 of 10"
  , MkLogLine "stdout>" "Finalizing..."
  , MkLogLine "stdout>" "Task completed successfully"
  , MkLogLine "stdout>" "Exit code: 0"
  ]

failedLogs : String -> List LogLine
failedLogs name = [
    MkLogLine "stderr>" "Error: Task '\{name}' failed"
  , MkLogLine "stderr>" "Command returned non-zero exit code"
  , MkLogLine "stderr>" "Retrying (attempt 1 of 2)..."
  , MkLogLine "stderr>" "Retry failed"
  , MkLogLine "stderr>" "Max retries reached. Giving up."
  ]

runningLogs : String -> List LogLine
runningLogs name = [
    MkLogLine "stdout>" "Starting task: \{name}"
  , MkLogLine "stdout>" "Working..."
  , MkLogLine "stdout>" "Processing item 1 of 5"
  , MkLogLine "stdout>" "Processing item 2 of 5"
  , MkLogLine "stdout>" "Processing item 3 of 5"
  , MkLogLine "stdout>" "(still running...)"
  , MkLogLine "stdout>" ""
  , MkLogLine "stdout>" ""
  ]

public export
loadMockLogs : JobEntry -> IO (List LogLine)
loadMockLogs entry = pure $ case entry.status of
  SUCCESS   => successLogs entry.task.name
  FAILED    => failedLogs entry.task.name
  TIMEDOUT  => [MkLogLine "stderr>" "Timed out"]
  RUNNING   => runningLogs entry.task.name
  QUEUED    => []
  CANCELLED => [MkLogLine "stdout>" "Cancelled"]

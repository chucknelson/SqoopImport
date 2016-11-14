#!/usr/bin/env bash

### Bash script helpers
# Error handling 

# Variables
RC=0;
RCSUM=0
ERRCNT=0

# Functions
# showRCSummary
showRCSummary() {
  logHeader "Return Code Summary: Last RC: $RC, Error Count: $ERRCNT, RC Sum: $RCSUM"
}

# captureRC <Return Code>
captureRC() {
  RC=$1
  RCSUM=$(($RCSUM+$RC))
  if [[ $RC > 0 ]]
  then
    ERRCNT=$((ERRCNT+1))
  fi
}

# try <Command [args]>
try() {
  set +e
  "$@"
  captureRC $?
  set -e
}

# errorExit <Exit Code>
errorExit() {
  local exitCode=$1
  logError "Exiting (exit code $exitCode)"
  exit $exitCode
}

# checkNumArguments <Number of Args> <Expected Number of Args> <Message>
checkNumArguments() {
  if [[ $1 -ne $2 ]]
  then
    logError "Invalid number of arguments ($1). $3"
    return 1 
  fi
}

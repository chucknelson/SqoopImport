#!/usr/bin/env bash

### Bash script helpers
# Error handling 

# Variables
RC=0;
RCSUM=0

# Functions
captureRC() {
  RC=$1
  RCSUM=$(($RCSUM+$RC))
}

# errorExit <Exit Code>
errorExit() {
  local exitCode=$1
  logError "Exiting (exit code $exitCode)"
  exit $exitCode
}

# checkNumArgument <Number of Args> <Expected Number of Args> <Message>
checkNumArguments() {
  if [[ $1 -ne $2 ]]
  then
    logError "Invalid number of arguments ($1). $3"
    return 1 
  fi
}




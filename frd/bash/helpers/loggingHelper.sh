#!/usr/bin/env bash

### Bash script helpers
# Logging 

# Standard logging functions
log () {
  echo -e "$helperOutputPrefix$1"
}

logInfo () {
  log " - INFO: $1"
}

logError () {
  log " - ERROR: $1"
}

logHeader () {
  logInfo "****************************************"
  logInfo "*** $1"
  logInfo "****************************************"
}


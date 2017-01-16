#!/usr/bin/env bash

### Bash script helpers
# Logging 

# Standard logging functions
log () {
  echoWithPrefix "$1"
}

logInfo () {
  log " - INFO: $1"
}

logError () {
  >&2 log " - ERROR: $1"
}

logHeader () {
  logInfo "****************************************"
  logInfo "*** $1"
  logInfo "****************************************"
}


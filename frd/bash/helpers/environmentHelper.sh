#!/usr/bin/env bash

### Bash script helpers
# Environment 

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color


# Functions
getCurrentPathCmd() {
  declare -n returnValue=$1
  local currentPathCmd='cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd'
  returnValue=$currentPathCmd
}

getCurrentDate() {
  declare -n returnValue=$1
  returnValue="$( date '+%Y/%m/%d %r' )"
}

#!/usr/bin/env bash
VERSION="0.9.2"

### Script Safety
# Exit script if any variable is not set
set -o nounset

# Exit script if any errors encountered (to avoid cascading errors)
set -o errexit

# Pass along exit code if ANY command in a piped command fails (not just the last one)
set -o pipefail

### Bash script helpers

helperVerboseOn() {
  export BASH_HELPER_VERBOSE=1
}

helperVerboseOff() {
  export BASH_HELPER_VERBOSE=0
}

helperVerboseEnabled() {
  [[ ${BASH_HELPER_VERBOSE+x} && "$BASH_HELPER_VERBOSE" > 0 ]]
}

# "Global" echo function
echoWithPrefix() {
  local helperOutputPrefix="date '+%Y/%m/%d %r'"
  echo -e "$( eval $helperOutputPrefix )$1"
}

# Echo function for verbose mode
echoVerbose() {
  if helperVerboseEnabled
  then
    echoWithPrefix "$1"
  fi
}

if [[ ${helperVersion+x} ]]
then
  echoVerbose " - bash helpers (v$helperVersion) already loaded"
else
  echoVerbose " - Initializing script $1"

  helperVersion="$VERSION" # to avoid possible conflicts
  echoVerbose " - Initializing bash helpers (v$helperVersion)"

  # Initialize all helpers 
  helperPath="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

  for helper in "$helperPath"/*Helper.sh; do
    echoVerbose " - Initialized $helper"
    source "$helper"
  done

  echoVerbose " - Initialization complete"  
fi

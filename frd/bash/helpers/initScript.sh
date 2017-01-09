#!/usr/bin/env bash
VERSION="0.9.1"
helperVersion="$VERSION" # to avoid possible conflicts

### Script Safety
# Exit script if any variable is not set
set -o nounset

# Exit script if any errors encountered (to avoid cascading errors)
set -o errexit

# Pass along exit code if ANY command in a piped command fails (not just the last one)
set -o pipefail

### Bash script helpers

echoWithPrefix() {
  local helperOutputPrefix="date '+%Y/%m/%d %r'"
  echo -e "$( eval $helperOutputPrefix )$1"
}

if [[ ${helperOutputPrefix+x} ]]
then
  echoWithPrefix "bash helpers (v$helperVersion) already loaded"
else
  echoWithPrefix " - Initializing script $1"

  # Initialize all helpers 
  helperPath="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

  echoWithPrefix " - Initializing bash helpers (v$helperVersion)"

  for helper in "$helperPath"/*Helper.sh; do
    echoWithPrefix " - Initialized $helper"
    source "$helper"
  done

  echoWithPrefix " - Initialization complete"  
fi

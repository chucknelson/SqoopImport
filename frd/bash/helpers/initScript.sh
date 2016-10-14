#!/usr/bin/env bash

### Script Safety
# Exit script if any variable is not set
set -o nounset

# Exit script if any errors encountered (to avoid cascading errors)
set -o errexit

# Pass along exit code if ANY command in a piped command fails (not just the last one)
set -o pipefail

currentTimestamp="$( date '+%Y/%m/%d %r' )"
echo "$currentTimestamp - Initializing script $1"

### Bash script helpers
# Initialize all helpers 

helperPath="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

echo "$currentTimestamp - Initializing helpers"

for helper in $helperPath/*Helper.sh; do
  echo "$currentTimestamp - Initialized $helper"
  source $helper
done



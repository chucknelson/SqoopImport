#!/usr/bin/env bash
VERSION="0.9"

### Script Safety
# Exit script if any variable is not set
set -o nounset

# Exit script if any errors encountered (to avoid cascading errors)
set -o errexit

# Pass along exit code if ANY command in a piped command fails (not just the last one)
set -o pipefail

### Bash script helpers

helperVersion="$VERSION"
helperOutputPrefix="$( date '+%Y/%m/%d %r' )"
echo "$helperOutputPrefix - Initializing script $1"

# Initialize all helpers 
helperPath="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

echo "$helperOutputPrefix - Initializing bash helpers (v$helperVersion)"

for helper in "$helperPath"/*Helper.sh; do
  echo "$helperOutputPrefix - Initialized $helper"
  source "$helper"
done

echo "$helperOutputPrefix - Initialization complete"

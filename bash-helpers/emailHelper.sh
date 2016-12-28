#!/usr/bin/env bash

### Bash script helpers
# Email 

### Functions
# sendEmail <From> <To> <Subject> <Body>
sendEmail () {
  if checkNumArguments $# 4 "Function sendEmail() expected <From> <To> <Subject> <Body>"
  then
    logInfo "$4" | mail -a "From: $1" -s "$3" "$2"
  else
    return 1
  fi
}

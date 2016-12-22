#!/usr/bin/env bash

# Sqoop Import
# Imports single or multiple database tables provided by the user.
# Required: Configuration file, Hive database already created (if importing into Hive)

# Usage: bash sqoopImport.sh [config file] [import file directory]

# Author(s): Chuck Nelson

### Initialize Script
set -e
trap 'echo "Error intializing script, exit code: $?"; exit;' INT TERM EXIT

### Initialize Script and Script Helpers
# This allows relative paths to work regardless of where this script is called
currentPath="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
currentScript=`basename "$0"`

# Initialize script and helpers
source ~/.bash/helpers/initScript.sh "$currentScript"
trap - INT TERM EXIT
### End Initialize Script

#--------------------

# Script arguments / config
# Defaults
DEFAULT_CONFIG="sqoop_import.cfg"
DEFAULT_TABLE_LIST="table_list.txt"

# parseOptions [options/parameters]
parseOptions() {
  while [[ $# -gt 0 ]]
  do
    key="$1"
    case "$key" in
      -c|--configfilename)
      configFileName="$2"
      shift # past option
      ;;
      -i|--importfiledir)
      importFileDir="$2"
      shift # past option
      ;;
      *)
      echo "Unknown option: $key"
      errorExit 1 # something went wrong with the options
      ;;
    esac
    shift # past argument or value
  done
}

setImportFileDir() {
  if [ -z ${importFileDir+x} ]
  then
    logInfo "Import file directory not specified, using current execution directory: $currentPath"
    importFileDir="$currentPath"
  fi

  logInfo "Using import file directory of: $importFileDir"
}

loadConfig() {
  if [ -z ${configFileName+x} ]
  then
    logInfo "Configuration file not specified, attempting to use default of $DEFAULT_CONFIG"
    configFileName="$DEFAULT_CONFIG"
  fi

  configFileName="$importFileDir/$configFileName"

  if [ ! -f "$configFileName" ]
  then
    logError "Configuration file $configFileName not found"
    errorExit 1
  fi

  # Load config
  logInfo "Using configuration specified in: $configFileName"
  source "$configFileName"
}

loadTableList() {
  # Check for individual table
  if [ -z ${tableName+x} ]
  then
    logInfo "Individual table not specified, attempting to use table list"
  else
    logInfo "Importing individual table: $tableName"
    tableList=("$tableName")
    return 0
  fi

  if [ -z ${tableListFileName+x} ]
  then
    logInfo "Table list file not specified, attempting to use default of $DEFAULT_TABLE_LIST"
    tableListFileName="$DEFAULT_TABLE_LIST"
  fi

  tableListFileName="$importFileDir/$tableListFileName"

  if [ ! -f "$tableListFileName" ]
  then
    logError "Table list file $tableListFileName not found"
    errorExit 1
  fi

  # Read list of tables into an array we can loop through
  logInfo "Importing from table list: $tableListFileName"
  mapfile -t tableList < "$tableListFileName"
}

# Init
parseOptions "$@"
setImportFileDir
loadConfig
loadTableList

#-----

# Build Sqoop command
# See: http://unix.stackexchange.com/questions/152553/bash-string-concatenation-used-to-build-parameter-list
# Command variable: sqoopCommand
# Command parameters array: sqoopCommandParams

buildImportTypeOptions() {
  if [[ "$importType" == "table" ]]
  then
    sqoopCommandParams+=("--table $activeTable")
  elif [[ "$importType" == "query" ]]
  then
    local parsedQueryString="${queryString/\$TABLE/$activeTable}"
    parsedQueryString="${parsedQueryString/\$CONDITIONS/\\\$CONDITIONS}"
    sqoopCommandParams+=("--query \"$parsedQueryString\"")
  else
    logError "Invalid import type: $importType"
    errorExit 1
  fi
}

buildConnectionOptions() {
  sqoopCommandParams+=("-Dhadoop.security.credential.provider.path=$hadoopCredentialPath")
  sqoopCommandParams+=("--connect \"$dbConnectionString\"")
  sqoopCommandParams+=("--username $dbUserName")
  sqoopCommandParams+=("--password-alias $dbCredentialName")
}

buildDestinationOptions() {
  sqoopCommandParams+=("--target-dir $tableDestinationDir")
}

buildMapperOptions() {
  sqoopCommandParams+=("--num-mappers 1")
}

buildHiveOptions() {
  sqoopCommandParams+=("--hive-import")
  sqoopCommandParams+=("--hive-database $destinationHiveDB")
  sqoopCommandParams+=("--hive-table $activeTable")
  sqoopCommandParams+=("--hive-overwrite")
  sqoopCommandParams+=("--null-string '\\\N'")
  sqoopCommandParams+=("--null-non-string '\\\N'")
  sqoopCommandParams+=("--hive-drop-import-delims")
}

buildSqoopCommand() {
  sqoopCommandParams=("import")
  #TODO Build according to other options (i.e., do we want to import into Hive or not)
  buildConnectionOptions
  buildDestinationOptions
  buildMapperOptions
  buildHiveOptions
  buildImportTypeOptions

  sqoopCommand="$( echo "sqoop ${sqoopCommandParams[@]}" )"
}

# Imports table via a dynamic/built Sqoop command
# importTable
importActiveTable() {
  buildSqoopCommand

  logInfo "Importing table: $dbName.$dbSchemaName.$activeTable"
  logInfo "Hive destination: $destinationHiveDB.$activeTable"
  logInfo "Removing prior staging data in: $tableDestinationDir"
  hadoop fs -rm -f -R "$tableDestinationDir"
  
  logInfo "Running Sqoop command:"
  echo "$sqoopCommand"
  eval "$sqoopCommand"
}

for table in "${tableList[@]}"; do
  activeTable="$table"
  tableDestinationDir="$destinationDir"/"$activeTable"

  try importActiveTable
  logInfo "Import complete for table: $dbName.$dbSchemaName.$activeTable - RC: $RC"
done

logInfo "All imports complete - Error Count: $ERRCNT"

# If we encountered any errors (via try()), exit with error status
exitWithErrorCheck
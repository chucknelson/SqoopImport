#!/usr/bin/env bash
VERSION="0.9.1"

# Sqoop Import
# Imports single or multiple database tables provided by the user.
# Required: Configuration file, Hive database already created (if importing into Hive)

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

# Defaults
DEFAULT_CONFIG="sqoop_import.cfg"
DEFAULT_TABLE_LIST="table_list.txt"

# Script Info
USAGE="
Wrapper for Sqoop imports that uses a configuration file and an optional list of tables. This was created to reduce the number of individual hard-coded Sqoop jobs, as well as provide a tested, standard way to launch non-persistent/non-incremental Sqoop jobs.

Usage: $currentScript [OPTIONS]

Available options:
  -c | --configfilename  Name of Sqoop import configuration file to use
  -h | --help            Display usage information
  -i | --importfiledir   Directory/location of import files (e.g., configuration file, table list)
  -v | --version         Display version information
"

# Script arguments / config
showVersionInfo() {
  logInfo "$currentScript ($VERSION)"
}

showUsageInfo() {
  echo "$USAGE" >&2 # output to STDERR
}

# parseOptions [script arguments]
parseOptions() {
  if [[ $# == 0 ]]
  then
    set -- "--help" # if no arguments, default to help
  fi

  while [[ $# -gt 0 ]]
  do
    key="$1"
    case "$key" in
      -c|--configfilename)
        configFileName="$2"
        shift # past option
        ;;
      -h|--help)
        showVersionInfo
        showUsageInfo
        exit 0
      ;;
        -i|--importfiledir)
        importFileDir="$2"
        shift # past option
      ;;
        -v|--version)
        showVersionInfo
        exit 0
      ;;
      *)
        showUsageInfo
        logError "Unknown option: $key"
        errorExit 1 # something went wrong with the options
      ;;
    esac
    shift # past option or value
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

# Options
parseOptions "$@"

# Init
showVersionInfo
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
  
  case "$destinationType" in
    "hive")
      logInfo "Data staging destination: $tableDestinationDir"
      logInfo "Hive destination: $destinationHiveDB.$activeTable"

      sqoopCommandParams+=("--hive-import")
      sqoopCommandParams+=("--hive-database $destinationHiveDB")
      sqoopCommandParams+=("--hive-table $activeTable")
      sqoopCommandParams+=("--hive-overwrite")
      sqoopCommandParams+=("--null-string '\\\N'")
      sqoopCommandParams+=("--null-non-string '\\\N'")
      sqoopCommandParams+=("--hive-drop-import-delims")
      ;;
    "hdfs")
      logInfo "Data destination: $tableDestinationDir"
      ;;
    *)
      logError "Invalid destination type: $destinationType"
      errorExit 1
      ;;
  esac
}

buildMapperOptions() {
  sqoopCommandParams+=("--num-mappers 1")
}

buildSqoopCommand() {
  sqoopCommandParams=("import")
  #TODO Build according to other options (i.e., do we want to import into Hive or not)
  buildConnectionOptions
  buildMapperOptions
  buildDestinationOptions
  buildImportTypeOptions

  sqoopCommand="$( echo "sqoop ${sqoopCommandParams[@]}" )"
}

# Imports table via a dynamic/built Sqoop command
# importTable
importActiveTable() {
  logInfo "Importing table: $dbName.$dbSchemaName.$activeTable"
  buildSqoopCommand
  
  logInfo "Prior data in: $tableDestinationDir"
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
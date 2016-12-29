#!/usr/bin/env bash
VERSION="0.9.4-wip"

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

# Constants / Refs
DEST_TYPE_HDFS="hdfs"
DEST_TYPE_HIVE="hive"
IMPORT_TYPE_QUERY="query"
IMPORT_TYPE_TABLE="table"
JDBC_NETEZZA_STRING="jdbc:netezza"
JDBC_SQLSERVER_STRING="jdbc:sqlserver"

# Defaults
DEFAULT_CONFIG="sqoop_import.cfg"
DEFAULT_TABLE_LIST="table_list.txt"
DEFAULT_MAPPERS=1

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
  if [[ ! "$importFileDir" ]]
  then
    logInfo "Import file directory not specified, using current execution directory: $currentPath"
    importFileDir="$currentPath"
  fi

  logInfo "Using import file directory of: $importFileDir"
}

loadConfig() {
  if [[ ! "$configFileName" ]]
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
  if [[ ! "$tableName" ]]
  then
    logInfo "Individual table not specified, attempting to use table list"
  else
    logInfo "Importing individual table: $tableName"
    tableList=("$tableName")
    return 0
  fi

  if [[ ! "$tableListFileName" ]]
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

  numTables="${#tableList[@]}"
  logInfo "Importing $numTables table(s)"
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

initSqoopCommand() {
  sqoopCommandParams=("import")
}

buildImportTypeOptions() {
  case "$importType" in
    "$IMPORT_TYPE_TABLE")
      sqoopCommandParams+=("--table $activeTable")
      ;;
    "$IMPORT_TYPE_QUERY")
      local parsedQueryString="${queryString/\$TABLE/$activeTable}"
      parsedQueryString="${parsedQueryString/\$CONDITIONS/\\\$CONDITIONS}"
      sqoopCommandParams+=("--query \"$parsedQueryString\"")
      ;;
    *)
      logError "Invalid import type: $importType"
      errorExit 1
      ;;
  esac
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
    "$DEST_TYPE_HDFS")
      logInfo "Data destination: $tableDestinationDir"
      sqoopCommandParams+=("--optionally-enclosed-by '\\\"'")
      ;;
    "$DEST_TYPE_HIVE")
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
    *)
      logError "Invalid destination type: $destinationType"
      errorExit 1
      ;;
  esac
}

buildMapperOptions() {
  # Number of mappers to use
  if [[ ! "$numMappers" ]]
  then
    logInfo "Number of mappers not specified, using default of $DEFAULT_MAPPERS"
    numMappers=$DEFAULT_MAPPERS
  else
    logInfo "Using $numMappers mapper(s)"
  fi
  sqoopCommandParams+=("--num-mappers $numMappers")

  # How to split data if more than 1 mapper
  if [[ "$importType" == "query" && "$numMappers" > 1 ]]
  then
    if [[ "$numTables" > 1 ]]
    then
      logError "Query imports with multiple mappers are currently allowed with single table imports only"
      errorExit 1
    fi
      
    if [[ ! "$splitByColumn" ]]
    then
      logError "splitByColumn not found - Query imports with multiple mappers require a split-by column"
      errorExit 1
    fi
    # Query imports must have an explicit split-by column for multiple mappers
    sqoopCommandParams+=("--split-by $splitByColumn")
  else
    # Table import auto-split by primary key, and this option protects against tables with no primary key
    sqoopCommandParams+=("--autoreset-to-one-mapper")
  fi
}

buildCustomOptions() {
  sqoopCommandParams+=("--")

  if [[ "$dbConnectionString" =~  "$JDBC_SQLSERVER_STRING" ]]
  then
    sqoopCommandParams+=("--schema $dbSchemaName")
  fi
}

buildSqoopCommand() {
  initSqoopCommand
  buildConnectionOptions
  buildMapperOptions
  buildDestinationOptions
  buildImportTypeOptions

  # Custom options are always added last
  buildCustomOptions

  sqoopCommand="$( echo "sqoop ${sqoopCommandParams[@]}" )"
}

#-----

# Execute Commands

# Imports table via a dynamic/built Sqoop command
# importActiveTable
importActiveTable() {
  logInfo "Importing table: $dbName.$dbSchemaName.$activeTable"
  buildSqoopCommand
  
  logInfo "Deleting existing import data in: $tableDestinationDir"
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
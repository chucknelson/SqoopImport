#!/usr/bin/env bash
VERSION="1.0.0"
sqoopImportVersion="$VERSION" # to avoid possible conflicts

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
IMPORT_TYPE_JOB="job"
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
  logInfo "$currentScript (v$sqoopImportVersion)"
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
  if [[ ! ${importFileDir+x} || ! "$importFileDir" ]]
  then
    logInfo "Import file directory not specified, using current execution directory: $currentPath"
    importFileDir="$currentPath"
  fi

  logInfo "Using import file directory of: $importFileDir"
}

loadConfig() {
  if [[ ! ${configFileName+x} || ! "$configFileName" ]]
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
  if [[ ! ${tableName+x} ||  ! "$tableName" ]]
  then
    logInfo "Individual table not specified, attempting to use table list"
  else
    logInfo "Importing individual table: $tableName"
    tableList=("$tableName")
    return 0
  fi

  if [[ ! ${tableListFileName+x} || ! "$tableListFileName" ]]
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

if [[ "$importType" != "$IMPORT_TYPE_JOB" ]]
then
  loadTableList
fi

#-----

# Build Sqoop command
# See: http://unix.stackexchange.com/questions/152553/bash-string-concatenation-used-to-build-parameter-list
# Command variable: sqoopCommand
# Command parameters array: sqoopCommandParams

varIsAvailable() {
  local var="$1"
  [[ ${!var+x} && ${!var} ]]
}

stagingEnabled() {
  if varIsAvailable destinationType && [[ "$destinationType" == "$DEST_TYPE_HIVE" ]]
  then
    logInfo "Staging occurs automatically with Hive imports, ignoring staging settings"
    return 1
  else
    varIsAvailable stagingDir
  fi
}

overwriteEnabled() {
  varIsAvailable destinationDirOverwrite && [[ "$destinationDirOverwrite" == "true" ]]
}

addEmptySqoopParameter() {
  local parameter="$1"
  logInfo "Adding parameter: $parameter"
  sqoopCommandParams+=("$parameter")
}

# Add Sqoop parameter if value exists
# This allows us to interpret/continue processing with missing or blank config values
# addSqoopParameter [parameter] [value]
addSqoopParameter() {
  local parameter="$1"
  local value="$2"

  # Strip quotes on value for checking existence (could just be empty quotes)
  local valueToCheck="$(sed -e 's/^"//' -e 's/"$//' <<<"$value")"

  if [[ "$parameter" && "$valueToCheck" ]]
  then  
    local paramString="$parameter $value"
    if [[ "$parameter" =~ "Dhadoop" ]]
    then
      # Generic parameters use "=" syntax
      paramString="$parameter=$value"
      logInfo "Adding parameter: $paramString"
      sqoopCommandParams+=("$paramString")
    else
      logInfo "Adding parameter: $paramString"
      sqoopCommandParams+=("$paramString")
    fi
  fi
}

initSqoopCommand() {
  case "$importType" in
    "$IMPORT_TYPE_JOB")
      sqoopCommandParams=("job")
      ;;
    "$IMPORT_TYPE_QUERY"|"$IMPORT_TYPE_TABLE")
      sqoopCommandParams=("import")
      ;;
    *)
      logError "Invalid import type: $importType"
      errorExit 1
      ;;
  esac 
}

buildGenericOptions() {
  addSqoopParameter "-Dhadoop.security.credential.provider.path" "$hadoopCredentialPath"
}

buildImportTypeOptions() {
  case "$importType" in
    "$IMPORT_TYPE_JOB")
      addSqoopParameter "--exec" "$jobName"
      addEmptySqoopParameter "--"  # to prepare for any overriding options in config
      ;;
    "$IMPORT_TYPE_TABLE")
      addSqoopParameter "--table" "$activeTable"
      ;;
    "$IMPORT_TYPE_QUERY")
      local parsedQueryString="${queryString/\$TABLE/$activeTable}"
      parsedQueryString="${parsedQueryString/\$CONDITIONS/\\\$CONDITIONS}"
      addSqoopParameter "--query" "\"$parsedQueryString\""
      ;;
    *)
      logError "Invalid import type: $importType"
      errorExit 1
      ;;
  esac
}

buildConnectionOptions() {
  addSqoopParameter "--connect" "\"$dbConnectionString\""
  addSqoopParameter "--username" "$dbUserName"
  addSqoopParameter "--password-alias" "$dbCredentialName"
}

buildMapperOptions() {
  # Number of mappers to use
  if ! varIsAvailable numMappers
  then
    if [[ "$importType" == "$IMPORT_TYPE_JOB" ]]
    then
      logInfo "Number of mappers not specified for job, using job's default"
    else
      logInfo "Number of mappers not specified for import, using default of $DEFAULT_MAPPERS"
      numMappers=$DEFAULT_MAPPERS
    fi
  fi
  
  logInfo "Using $numMappers mapper(s)"
  addSqoopParameter "--num-mappers" "$numMappers"

  # How to split data if more than 1 mapper
  if varIsAvailable splitByColumn
  then
    if [[ "$importType" != "$IMPORT_TYPE_JOB" ]]
    then
      # Table imports without "split-by" auto-split by primary key, and this option protects against tables with no primary key
      addEmptySqoopParameter "--autoreset-to-one-mapper"
    fi
  else
    addSqoopParameter "--split-by" "$splitByColumn"  
  fi
}

buildDestinationOptions() {
  if stagingEnabled
  then
    addSqoopParameter "--target-dir" "$tableStagingDir"  
  else
    addSqoopParameter "--target-dir" "$tableDestinationDir"  
  fi
  
  if [[ "$destinationType" ]]
  then
    case "$destinationType" in
      "$DEST_TYPE_HDFS")
        logInfo "Data destination: $tableDestinationDir"
        addSqoopParameter "--optionally-enclosed-by" "'\\\"'"
        ;;
      "$DEST_TYPE_HIVE")
        logInfo "Hive data staging destination: $tableDestinationDir"
        logInfo "Hive destination: $destinationHiveDB.$activeTable"
        addEmptySqoopParameter "--hive-import"
        addSqoopParameter "--hive-database" "$destinationHiveDB"
        addSqoopParameter "--hive-table" "$activeTable"
        addEmptySqoopParameter "--hive-overwrite"
        addSqoopParameter "--null-string" "'\\\N'"
        addSqoopParameter "--null-non-string" "'\\\N'"
        addEmptySqoopParameter "--hive-drop-import-delims"
        ;;
      *)
        logError "Invalid destination type: $destinationType"
        errorExit 1
        ;;
    esac
  fi
}

buildCustomOptions() {
  addEmptySqoopParameter "--"

  if [[ "$dbConnectionString" =~  "$JDBC_SQLSERVER_STRING" ]]
  then
    addSqoopParameter "--schema" "$dbSchemaName"
  fi
}

buildSqoopCommand() {
  # Temporarily allow unset variables - some config values can be missing
  set +u

  initSqoopCommand
  buildGenericOptions
  buildImportTypeOptions
  buildConnectionOptions
  buildMapperOptions
  buildDestinationOptions
  # Custom options are always added last
  buildCustomOptions

  # Restore error setting for unset variables
  set -u
  sqoopCommand="$( echo "sqoop ${sqoopCommandParams[@]}" )"
}

#-----

# Execute Commands
deleteHDFSLocation() {
  local location="$1"

  if overwriteEnabled
  then
    logInfo "Overwrite of data destination enabled"
    logInfo "Deleting existing data in: $location"
    hadoop fs -rm -f -R "$location"
  else
    logInfo "Overwriting of data destination disabled or not specified, $location will not be overwritten"
  fi
}

copyHDFSLocation() {
  local origin="$1"
  local destination="$2"

  logInfo "Copying $origin  =to=>  $destination"
  hadoop distcp "$origin" "$destination"
}

#TODO - Refactor?
setActiveHDFSLocations() {
  if stagingEnabled
  then
    if [[ "$importType" == "$IMPORT_TYPE_JOB" ]]
    then
      tableStagingDir="$stagingDir"
    else
      tableStagingDir="$stagingDir"/"$activeTable"
    fi
  fi

  if [[ "$importType" == "$IMPORT_TYPE_JOB" ]]
  then
    tableDestinationDir="$destinationDir"
  else
    tableDestinationDir="$destinationDir"/"$activeTable"
  fi
}

prepareDestination() {
  deleteHDFSLocation "$tableDestinationDir"
}

prepareStaging() {
  if stagingEnabled
  then
    logInfo "Staging import data in: $tableStagingDir"
    deleteHDFSLocation "$tableStagingDir"
  else
    logInfo "Staging directory not specified, data will be imported directly to the destination"
    prepareDestination
  fi
}

moveStaging() {
  if stagingEnabled
  then
    logInfo "Moving staging data to destination"
    prepareDestination
    copyHDFSLocation "$tableStagingDir" "$tableDestinationDir"
  else
    logInfo "Staging directory not specified, data was imported directly to the destination"
  fi
}

executeSqoopCommand() {
  buildSqoopCommand
  logInfo "Executing Sqoop command:"
  echo "$sqoopCommand"
  
  prepareStaging
  
  if eval "$sqoopCommand"
  then
    moveStaging
  else
    return 1
  fi
}

executeSqoopJob() {
  logInfo "Executing Sqoop job: $jobName"
  executeSqoopCommand
}

# Imports table via a dynamic/built Sqoop command
# importActiveTable
importActiveTable() {
  logInfo "Importing table: $dbName.$dbSchemaName.$activeTable"
  executeSqoopCommand
}

if [[ "$importType" == "$IMPORT_TYPE_JOB" ]]
then
  setActiveHDFSLocations
  try executeSqoopJob
  logInfo "Job $jobName complete - RC: $RC"
else
  for table in "${tableList[@]}"; do
    activeTable="$table"
    setActiveHDFSLocations

    try importActiveTable
    logInfo "Import complete for table: $dbName.$dbSchemaName.$activeTable - RC: $RC"
  done
fi

logInfo "All imports complete - Error Count: $ERRCNT"

# If we encountered any errors (via try()), exit with error status
exitWithErrorCheck
#!/bin/bash

set -e

# Check and set missing environment vars
: ${S3_BUCKET:?"S3_BUCKET env variable is required"}
if [[ -z ${S3_KEY_PREFIX} ]]; then
  export S3_KEY_PREFIX=""
else
  if [ "${S3_KEY_PREFIX: -1}" != "/" ]; then
    export S3_KEY_PREFIX="${S3_KEY_PREFIX}/"
  fi
fi
echo $S3_KEY_PREFIX
export DATABASE_PATH=${DATABASE_PATH:-/data/sqlite3.db}
export BACKUP_PATH=${BACKUP_PATH:-${DATABASE_PATH}.bak}
export DATETIME=$(date "+%Y%m%d%H%M%S")
export RANDOMIZER=${RANDOM:0:3}

# Add this script to the crontab and start crond
cron() {
  echo "Starting backup cron job with frequency '$1'"
  echo "$1 $0 sleep $RANDOMIZER backup" > /var/spool/cron/crontabs/root
  crond -f
}

# Dump the database to a file and push it to S3
backup() {
  # Dump database to file
  echo "Backing up $DATABASE_PATH to $BACKUP_PATH"
  sqlite3 $DATABASE_PATH ".backup $BACKUP_PATH"
  if [ $? -ne 0 ]; then
    echo "Failed to backup $DATABASE_PATH to $BACKUP_PATH"
    exit 1
  fi

  echo "Sending file to S3"
  # Push backup file to S3
  if aws s3 rm s3://${S3_BUCKET}/${S3_KEY_PREFIX}latest.bak; then
    echo "Removed latest backup from S3"
  else
    echo "No latest backup exists in S3"
  fi
  if aws s3 cp $BACKUP_PATH s3://${S3_BUCKET}/${S3_KEY_PREFIX}latest.bak; then
    echo "Backup file copied to s3://${S3_BUCKET}/${S3_KEY_PREFIX}latest.bak"
  else
    echo "Backup file failed to upload"
    exit 1
  fi

  echo "Done"
}

# Pull down the latest backup from S3 and restore it to the database
restore() {
  # Get backup file from S3
  echo "Downloading latest backup from S3"
  if aws s3 cp s3://${S3_BUCKET}/${S3_KEY_PREFIX}latest.bak $BACKUP_PATH; then
    echo "Downloaded"

    # Restore database from backup file
    echo "Running restore"
    mv $BACKUP_PATH $DATABASE_PATH
    echo "Done"
  else
    echo "Failed to download latest backup. Adding empty file and exiting"
    touch $DATABASE_PATH
    echo "Done"
    exit 0
  fi

}

# Handle command line arguments
case "$1" in
  "cron")
    cron "$2"
    ;;
  "backup")
    backup
    ;;
  "restore")
    restore
    ;;
  *)
    echo "Invalid command '$@'"
    echo "Usage: $0 {backup|restore|cron <pattern>}"
esac

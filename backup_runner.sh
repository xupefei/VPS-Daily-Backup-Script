#!/bin/bash

# This script will redirect the output data into file, and try to determine whether there exists any error.
# If it does, emails will be send to administrators.

ADMIN_MAIL=("yourname1@example.com" "yourname2@example.com")
SCRIPT_DIR=$(cd "$(dirname "$0")"; pwd)

/bin/bash $SCRIPT_DIR/backup.sh > $SCRIPT_DIR/backup.log

if cat $SCRIPT_DIR/backup.log | grep -iq "error:"
then
    # Send notification to administrators
    for m in "${ADMIN_MAIL[@]}"
    do
        mail -s "$(date +%Y-%m-%d): Backup error occurred" $m < $SCRIPT_DIR/backup.log
    done
else
    echo "Everything is okay."
fi

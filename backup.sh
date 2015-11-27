#!/bin/bash

# Automatic Backup Script by Paddy Xu, 22/07/2014
# 
# *) OVERVIEW
# 
# This script is designed to perform backup operation of web-files, databases 
# and important configuration files on a daily basis. A full backup will be performed 
# once a month, while incremental backups is performed on the rest days of the month. 
# This script should be run by Cron service, and if necessary, manually.
# 
# *) REQUIREMENTS
# 
#     *) 7-zip full package
#     *) Well-configured sendmail service
# 
# *) LOGIC
# 
# While preforming a full backup, the script will do the following task:
#     *) Close BBS
#     *) Backup databases
#     *) Backup all files
#     *) Reopen BBS
#     *) Remove full and incremental backup files of last month
# 
# If now an incremental backup task is running, the following steps will be performed:
#     *) Close BBS
#     *) Backup binary log of databases, based on the latest full backup
#     *) Do incremental backup for files, based on the latest full backup
#     *) Reopen BBS
# 
# Noticeably, the incremental backup is always based on the latest full backup, which 
# means that an existing incremental backup can be replaced by a latter incremental backup, 
# if they are both performed in the same month.
# 
# The relation between full and incremental backup can be described as the following graph:
# 
#       +-------------------------------+-------------------------------+
#       |              Jan              |              Feb              |
#       +-------------------------------+-------------------------------+
#       ^ Full 1
#        ^------^ Incremental 1.1
#        ^--------------^ Incremental 1.2
#        ^----------------------^ Incremental 1.3
#       +-------------------------------+-------------------------------+
#                                       ^ Full 2
#                                        ^------^ Incremental 2.1
#                                        ^--------------^ Incremental 2.2
#                                        ^----------------------^ Incremental 2.3
#       +-------------------------------+-------------------------------+
#                                                                       ^ Full 3
# 

SCRIPT_DIR=$(cd "$(dirname "$0")"; pwd)

ENCRYPT_KEY='GkU0Jx3^l004'

# server configurations
SQL_USER='root'
SQL_PASS='MmW7830@Vb8&'
DATABASE_NAME=("database1" "database2" "database3" "database4")
FILE_DIR_NAME=("git"          "web"               "nginx"                    "php"                   "etc" )
FILE_DIR=(     "/home/git"    "/home/wwwroot"     "/usr/local/nginx/conf"    "/usr/local/php/etc"    "/etc")
FILE_DIR_LENGTH=${#FILE_DIR_NAME[@]}
CK_LOCK_FILE=/home/wwwroot/example.com/maintain.lock
SQL_LOG_DIR=/usr/local/mariadb/var
BACKUP_DIR=$SCRIPT_DIR/data
FULL_BACKUP_BASE_DIR=$BACKUP_DIR/full
INCR_BACKUP_BASE_DIR=$BACKUP_DIR/incremental

CURRENT_MONTH=$(date +%Y-%m)
CURRENT_DAY=$(date +%Y-%m-%d)
LAST_MONTH=$(date -d last-month +%Y-%m)
YESTERDAY=$(date -d yesterday +%Y-%m-%d)

FULL_BACKUP_DIR=$FULL_BACKUP_BASE_DIR/$CURRENT_MONTH                #/home/backup/full/2014-01
INCR_BACKUP_MONTH_DIR=$INCR_BACKUP_BASE_DIR/$CURRENT_MONTH          #/home/backup/incremental/2014-01
INCR_BACKUP_DIR=$INCR_BACKUP_BASE_DIR/$CURRENT_MONTH/$CURRENT_DAY   #/home/backup/incremental/2014-01/2014-01-03
LAST_FULL_BACKUP_DIR=$FULL_BACKUP_BASE_DIR/$LAST_MONTH              #/home/backup/full/2013-12
LAST_INCR_BACKUP_DIR=$INCR_BACKUP_BASE_DIR/$LAST_MONTH              #/home/backup/incremental/2013-12

function shutdown_bbs {
    echo "Shutting down BBS..."
    touch $CK_LOCK_FILE
    sleep 5 # wait some time...
}

function reopen_bbs {
    echo "Reopening BBS..."
    sleep 5 # wait some time...
    rm -f $CK_LOCK_FILE
}

function func_full_backup {
    echo "Performing full backup..."
    
    # 
    # Delete existing backup files
    # 
    rm -rf $FULL_BACKUP_DIR/*
    rm -rf $INCR_BACKUP_MONTH_DIR/*
    
    rm -rf $LAST_FULL_BACKUP_DIR
    rm -rf $LAST_INCR_BACKUP_DIR
    
    # 
    # Databases
    # 
    echo "Deleting all database binary log files..."
    /usr/local/mariadb/bin/mysql -u$SQL_USER -p$SQL_PASS -e 'RESET MASTER'
    
    for db in "${DATABASE_NAME[@]}"
    do
        echo "Dumping ${db}..."
        /usr/local/mariadb/bin/mysqldump -u$SQL_USER -p$SQL_PASS --extended-insert=FALSE ${db} > $FULL_BACKUP_DIR/${db}.sql
    done
    
    echo "Rolling up databases..."
    7z a -mmt -mhe -mx3 -m0=PPMd -p$ENCRYPT_KEY $FULL_BACKUP_DIR/databases.7z $FULL_BACKUP_DIR/*.sql
    rm -f $FULL_BACKUP_DIR/*.sql
    
    echo "Database backup finished"
    
    # 
    # Files
    # 
    echo "Rolling up files..."
    for (( i=0; i<${FILE_DIR_LENGTH}; i++ ))
    do
        echo "${FILE_DIR_NAME[$i]}: ${FILE_DIR[$i]}:"
        7z a -r -mmt -mhe -mx3 -m0=PPMd -p$ENCRYPT_KEY $FULL_BACKUP_DIR/files_${FILE_DIR_NAME[$i]}.7z ${FILE_DIR[$i]}/*
    done
    
    echo "Files backup finished"
}

function func_incremental_backup {
    echo "Performing incremental backup based on full backup on $CURRENT_MONTH..."
    
    # 
    # Binary logs
    # 
    echo "Flushing binary log files..."
    /usr/local/mariadb/bin/mysql -u$SQL_USER -p$SQL_PASS -e 'FLUSH LOGS'
    echo "Copying binary logs..."
    temp=(`/usr/local/mariadb/bin/mysql -u$SQL_USER -p$SQL_PASS -B -N -e 'SHOW MASTER STATUS' | xargs`)
    current_log=./${temp[0]}
    all_logs=(`cat $SQL_LOG_DIR/mysql-bin.index | xargs`)
    
    for log in "${all_logs[@]}"
    do
        if [ "$log" == "$current_log" ] #Do not copy the log now is using
        then
            continue
        fi
        
        echo "Copying binary log $log"
        cp $SQL_LOG_DIR/$log $INCR_BACKUP_DIR/$log
    done
    
    echo "Rolling up binary logs..."
    7z a -mmt -mhe -mx3 -m0=PPMd -p$ENCRYPT_KEY $INCR_BACKUP_DIR/databases_inc.7z $INCR_BACKUP_DIR/mysql-bin.*
    rm -f $INCR_BACKUP_DIR/mysql-bin.*
    
    echo "Database backup finished"
    
    # 
    # Files
    # 
    echo "Rolling up files incrementally..."
    for (( i=0; i<${FILE_DIR_LENGTH}; i++ ))
    do
        echo "${FILE_DIR_NAME[$i]}: ${FILE_DIR[$i]}:"
        7z u $FULL_BACKUP_DIR/files_${FILE_DIR_NAME[$i]}.7z -r -mmt -mhe -mx3 -m0=PPMd -p$ENCRYPT_KEY -u- -up0q3r2x2y2z0w2\!$INCR_BACKUP_DIR/files_${FILE_DIR_NAME[$i]}_inc.7z ${FILE_DIR[$i]}/*
    done
    
    echo "Files backup finished"
}

echo "Starting, time is now $(date)"

mkdir -p $FULL_BACKUP_DIR
mkdir -p $INCR_BACKUP_DIR

shutdown_bbs

# If today is the 1st or 15th day of this month, do full backup. Otherwise, do incremental backup.
if [ `date +%d` == 01 ] || [ `date +%d` == 15 ]
then
    func_full_backup
else
    func_incremental_backup
fi

reopen_bbs
echo "Finished, time is now $(date)"

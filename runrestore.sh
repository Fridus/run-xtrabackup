#!/bin/sh

#############################
#  Functions
#############################
usage() {
cat << EOF
usage: $0 options

Prepare and restore a Mysql backup full|incremental.

OPTIONS:
   -b      Folder Full backup
   -u      User (default: dba)
   -p      User password (default: '')
      --password=...
   -h      Help

   --no-prepare   Don\'t prepare the backup
EOF
}

applyLogFull() {
   innobackupex --apply-log --redo-only $1 ${USEROPTIONS}
}

applyLogInc() {
   innobackupex --apply-log --redo-only $1 \
    --incremental-dir=$2 \
    ${USEROPTIONS}
}

#############################
#  Variables
#############################

BACKDIR="/nas/mysql/testb"

PREPARE=true

USER='dba'
PASSWORD=
dbpath=`cat /etc/mysql/my.cnf | grep innodb_data_home_dir | cut --delimiter='=' -f 2`
dbpathparent=`dirname $dbpath`
dbpathfoldername=`basename $dbpath`


while getopts “hb:u:p-:” OPTION
do
  case $OPTION in
    -)
      case "${OPTARG}" in
        password=*)
          val=${OPTARG#*=}
          PASSWORD=${val}
          ;;
        no-prepare)
          val=${OPTARG#*=}
          PREPARE=false
          ;;
      esac;;
    h)
      usage
      exit 1
      ;;
    b)
      BACKDIR=$OPTARG
      ;;
    u)
      USER=$OPTARG
      ;;
    p)
      OLDSTTY=$(stty -g)
      stty -echo
      read -p "Enter password: " PASSWORD
      stty $OLDSTTY
      echo
      ;;
    ?)
      usage
      exit
      ;;
  esac
done

BASEBACKDIR=$BACKDIR/base
INCRBACKDIR=$BACKDIR/incr
USEROPTIONS="--user=$USER --password=$PASSWORD"

if test ! -d $BASEBACKDIR
then
  error
  echo $BASEBACKDIR 'does not exist'; echo
  exit 1
fi

FULL=`find $BASEBACKDIR -mindepth 1 -maxdepth 1 -type d -printf "%P\n" | sort -nr | head -1` # latest
PATHFULL=${BASEBACKDIR}/${FULL}


#############################
#  Begin
#############################

## run skip networking to allow only connections on localhost
#stop mysql
#mysqld --skip-networking &

if [ $PREPARE = 'true' ]
then

  # Apply full
  echo 'Apply log FULL'
  applyLogFull $PATHFULL

  # Apply all incr
  if test -d $INCRBACKDIR/$FULL
  then
    BACKUPSINC=`find $INCRBACKDIR/$FULL -mindepth 1 -maxdepth 1 -type d -printf "%P\n" | sort -n`
    for BKI in $BACKUPSINC; do
      echo "Apply log INCR" $BKI
      applyLogInc $PATHFULL $INCRBACKDIR/$FULL/$BKI
    done
  fi

fi

# Copy
if test ! -d ${dbpathparent}/${dbpathfoldername}.bak
then
  echo "New directory: ${dbpathparent}/${dbpathfoldername}.bak"
  mkdir ${dbpathparent}/${dbpathfoldername}.bak
else
  rm -rf ${dbpathparent}/${dbpathfoldername}.bak/*
  echo "Remove: ${dbpathparent}/${dbpathfoldername}.bak/*"
fi

mv ${dbpathparent}/${dbpathfoldername}/* ${dbpathparent}/${dbpathfoldername}.bak/

innobackupex --copy-back $PATHFULL

chown -R mysql:mysql ${dbpath}

killall mysqld
stop mysql
start mysql

exit 0

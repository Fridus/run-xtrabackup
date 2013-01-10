 #!/bin/sh

usage() {
cat << EOF
usage: $0 options

Mysql backup full|incremental.

OPTIONS:
   -b      Folder Full backup (required)
   -f      Force full backup
      --full
   -h      Help
   -k      Keep this number of backups, appart form the one currently being incremented (default: 1)
   -l      Full backup live (3600)
   -p      User password (default: '')
      --password=...
   -u      User (default: dba)
EOF
}

#############################
#  Variables
#############################

TMPFILE="/tmp/innobackupex-runner.$$.tmp"
FILTERTABLES="--include=.*[.].*"
BACKDIR=
FULLBACKUPLIFE=3600   #604800 # How long to keep incrementing a backup for, minimum 60
KEEP=1                # Keep this number of backups, appart form the one currently being incremented
START=`date +%s`
USER='dba'
PASSWORD=
FULL=0

while getopts “hfb:u:pl:k:-:” OPTION
do
  case $OPTION in
    -)
      case "${OPTARG}" in
        password=*)
          val=${OPTARG#*=}
          PASSWORD=${val}
          ;;
        full)
          FULL=1
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
    l)
      FULLBACKUPLIFE=$OPTARG
      ;;
    k)
      KEEP=$OPTARG
      ;;
    f)
      FULL=1
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


#############################
#  Begin
#############################

echo "----------------------------"
echo
echo "innobackupex-runner.sh: MySQL backup script"
echo "started: `date`"
echo

# Check backuplife
if ! [ "$FULLBACKUPLIFE" -eq "$FULLBACKUPLIFE" ] 2>/dev/null;
then
  echo "Full backup life ($FULLBACKUPLIFE) is not an integer"
  exit 1
fi
if [ $FULLBACKUPLIFE -lt 60 ] || [ $FULLBACKUPLIFE -gt 604800 ]
then
  echo "Full backup life ($FULLBACKUPLIFE) must be greater or equal to 60 AND less than or equal to 604800"
  exit 1
fi

# Check base dir exists and is writable
if test ! -d $BASEBACKDIR -o ! -w $BASEBACKDIR
then
  error
  echo $BASEBACKDIR 'does not exist or is not writable'; echo
  exit 1
fi

# check incr dir exists and is writable
if test ! -d $INCRBACKDIR -o ! -w $INCRBACKDIR
then
  error
  echo $INCRBACKDIR 'does not exist or is not writable'; echo
  exit 1
fi

if [ -z "`mysqladmin $USEROPTIONS status | grep 'Uptime'`" ]
then
  echo "HALTED: MySQL does not appear to be running."; echo
  exit 1
fi

if ! `echo 'exit' | /usr/bin/mysql -s $USEROPTIONS`
then
  echo "HALTED: Supplied mysql username or password appears to be incorrect (not copied here for security, see script)"; echo
  exit 1
fi

echo "Check completed OK"

# Find latest backup directory
LATEST=`find $BASEBACKDIR -mindepth 1 -maxdepth 1 -type d -printf "%P\n" | sort -nr | head -1`

AGE=`stat -c %Y $BASEBACKDIR/$LATEST`


if [ "$LATEST" -a `expr $AGE + $FULLBACKUPLIFE + 5` -ge $START ] && [ $FULL -eq 0 ]
then
  echo 'New incremental backup'
  # Create an incremental backup

  # Check incr sub dir exists
  # try to create if not
  if test ! -d $INCRBACKDIR/$LATEST
  then
    mkdir $INCRBACKDIR/$LATEST
  fi

  # Check incr sub dir exists and is writable
  if test ! -d $INCRBACKDIR/$LATEST -o ! -w $INCRBACKDIR/$LATEST
  then
    echo $INCRBASEDIR 'does not exist or is not writable'
    exit 1
  fi

  LATESTINCR=`find $INCRBACKDIR/$LATEST -mindepth 1  -maxdepth 1 -type d | sort -nr | head -1`
  if [ ! $LATESTINCR ]
  then
    # This is the first incremental backup
    INCRBASEDIR=$BASEBACKDIR/$LATEST
  else
    # This is a 2+ incremental backup
    INCRBASEDIR=$LATESTINCR
  fi

  # Create incremental Backup
  innobackupex $USEROPTIONS $FILTERTABLES --incremental $INCRBACKDIR/$LATEST --incremental-basedir=$INCRBASEDIR > $TMPFILE 2>&1
else
  echo 'New full backup'
  # Create a new full backup
  innobackupex $USEROPTIONS $FILTERTABLES $BASEBACKDIR > $TMPFILE 2>&1
fi

if [ -z "`tail -1 $TMPFILE | grep 'completed OK!'`" ]
then
  echo "$INNOBACKUPEX failed:"; echo
  echo "---------- ERROR OUTPUT from $INNOBACKUPEX ----------"
  cat $TMPFILE
  rm -f $TMPFILE
  exit 1
fi

THISBACKUP=`awk -- "/Backup created in directory/ { split( \\\$0, p, \"'\" ) ; print p[2] }" $TMPFILE`

echo "Databases backed up successfully to: $THISBACKUP"
echo

MINS=$(($FULLBACKUPLIFE * ($KEEP + 1 ) / 60))
echo "Cleaning up old backups (older than $MINS minutes) and temporary files"

# Delete tmp file
rm -f $TMPFILE
# Delete old bakcups
for DEL in `find $BASEBACKDIR -mindepth 1 -maxdepth 1 -type d -mmin +$MINS -printf "%P\n"`
do
  echo "deleting $DEL"
  rm -rf $BASEBACKDIR/$DEL
  rm -rf $INCRBACKDIR/$DEL
done


SPENT=$(((`date +%s` - $START) / 60))
echo
echo "took $SPENT minutes"
echo "completed: `date`"
exit 0

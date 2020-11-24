#!/usr/bin/env bash

FLAG=0

function usage {
	cat <<EOF
Usage: $(basename "$0") [OPTION]...
  -t    Tool type: <snapshot|backup>
  -p    ZFS pool name
  -d    ZFS dataset name in pool(specified by -p), separated by comma: dataset1,dataset2
  -r    Remote ZFS pool name
  -l    Remote host login account(access through public key: root@172.16.66.66)
  -h    display help

EOF
    exit 2
}

function log {
    msg=$1
    /bin/date +"[%Y/%m/%d %H:%M:%S]: $msg" >> $LOG
}

function take_sanpshot {
    # $1: dataset name

    #now=$(date +"%Y%m%d-%H%M")
    now=$(date +"%Y%m%d-%H%M%S")
    log "[take_snapshot] Snapshot: $ZFS_POOL/$1@$now"
    zfs snapshot $ZFS_POOL/$1@$now
}

function check_backup {
    # $1: dataset name
    # $2: latest snapshot

    latest_backup=$(ssh $ZFS_REMOTE_LOGIN zfs list -t snap -H -p -s creation -o name | grep $1 | tail -1)
    latest_backup_ts=${latest_backup##*@}
    latest_snapshot_ts=${2##*@}

    if [ "$latest_snapshot_ts" == "$latest_backup_ts" ];then
        log "[INFO] latest_snapshot_ts($latest_snapshot_ts)==latest_backup_ts($latest_backup_ts), NO NEED TO BACKUP($1)."
        FLAG=1
    else
        FLAG=0
    fi
}

function send_init_snapshot {
    # $1: dataset name
    # $2: latest snapshot

    host=$(hostname)
    backup_name="$host-$1"

    log "[send_init_snapshot] Send: $2"
    zfs send $2 | ssh $ZFS_REMOTE_LOGIN zfs recv -F $ZFS_REMOTE_POOL/$backup_name
    ret=$?
    if [ $ret -ne 0 ];then
        log "[ERROR] send_init_snapshot failed, CHECK DATASET ON BACKUP HOST($1)"
    fi
}

function send_incremental_snapshot {
    # $1: dataset name

    latest_snapshot=($(zfs list -t snap -H -p -s creation -o name | grep "$ZFS_POOL/$1" | tail -1))
    latest_backup=$(ssh $ZFS_REMOTE_LOGIN zfs list -t snap -H -p -s creation -o name | grep $1)
    if [ -z "$latest_backup" ];then
        log "[INFO] NO BACKUP FOR DATASET($1), send_init_snapshot"
        send_init_snapshot $1 $latest_snapshot
    else
        log "[send_incremental_snapshot] Send: $ZFS_POOL/$1@$latest_backup_ts -> $latest_snapshot"
        host=$(hostname)
        backup_name="$host-$1"
        zfs send -i $ZFS_POOL/$1@$latest_backup_ts $latest_snapshot | ssh $ZFS_REMOTE_LOGIN zfs recv -F $ZFS_REMOTE_POOL/$backup_name
    fi

}


# Parse command line arguments
while getopts ":t:p:d:r:l:h" opt; do
    case "$opt" in
        t)
            TYPE=${OPTARG}
            (( $TYPE == "snapshot" || $TYPE == "backup" )) || usage
            ;;
        p)
            ZFS_POOL=$OPTARG
            ;;
        d)
            dataset_list=$OPTARG
            ;;
        r)
            ZFS_REMOTE_POOL=$OPTARG
            ;;
        l)
            ZFS_REMOTE_LOGIN=$OPTARG
            ;;
        h|*)
            usage
            ;;
    esac
done
if [ "$TYPE" == "snapshot" ];then
    if [ -z "${ZFS_POOL}" ] || [ -z "${dataset_list}" ];then
        usage
    fi
else
    if [ -z "${ZFS_POOL}" ] || [ -z "${dataset_list}" ] || [ -z "${ZFS_REMOTE_POOL}" ] || [ -z "${ZFS_REMOTE_LOGIN}" ]; then
        usage
    fi
fi

# Avoid globbing
set -f
ZFS_DATASETS=(${dataset_list//,/ })
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
LOG="$DIR/zfs.log"


if [ $TYPE == "snapshot" ];then
    for ds in "${ZFS_DATASETS[@]}"
    do
        take_sanpshot $ds
    done
else
    for ds in "${ZFS_DATASETS[@]}"
    do
        last_two_snapshots=($(zfs list -t snap -H -p -s creation -o name | grep "$ZFS_POOL/$ds" | tail -2))
        len=${#last_two_snapshots[@]}
        case "$len" in
            1)
                latest_snap=${last_two_snapshots[0]}
                check_backup $ds $latest_snap
                if [ "$FLAG" == 1 ];then
                    continue
                fi
                #send_init_snapshot $ds ${last_two_snapshots[0]}
                send_init_snapshot $ds $latest_snap
                ;;
            2)
                latest_snap=${last_two_snapshots[1]}
                check_backup $ds $latest_snap
                if [ "$FLAG" == 1 ];then
                    continue
                fi
                send_incremental_snapshot $ds 
                ;;
            *)
                log "[INFO] NO SNAPHOTS TO BACKUP($ds)"
                ;;
        esac
        #send_snapshot $ds
    done
fi





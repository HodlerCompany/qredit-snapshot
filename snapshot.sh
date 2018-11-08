#!/bin/bash

###############################################################################

# Inspired by Tharude (Ark.io) excellent ark_snapshot.sh script.
#
#
# - Save to /home/##USER##/snapshot.sh
#
# - chmod 700 /home/##USER##/snapshot.sh
#
# - Edit FinalDirectory variable
#   Make sure it's writable by snapshot user and readable by nginx user.
#
# - Edit Crontab
#      crontab -u ##USER## -e
#      2,17,32,47 * * * * /home/##USER##/snapshot.sh > /dev/null 2>&1 &
#
###############################################################################

QreditNetwork="db"
QreditNodeDirectory="$HOME/qredit-full-node"
SnapshotDirectory='/home/nayiem/snapshots'

### Test qredit-node Started
QreditNodePid=$( pgrep -a "node" | grep qredit-full-node | awk '{print $1}' )
if [ "$QreditNodePid" != "" ] ; then

    ### Delete Snapshot(s) older then 6 hours
    find $SnapshotDirectory -name "qredit_$QreditNetwork_*" -type f -mmin +360 -delete

    ### Write SeedNodeFile
#   QreditNodeConfig="$QreditNodeDirectory/config.$QreditNetwork.json"
    QreditNodeConfig="$QreditNodeDirectory/config.json"
    SeedNodeFile='/tmp/qredit_seednode'
    echo '' > $SeedNodeFile
    cat $QreditNodeConfig | jq -c -r '.peers.list[]' | while read Line; do
        SeedNodeAddress="$( echo $Line | jq -r '.ip' ):$( echo $Line | jq -r '.port' )"
        echo "$SeedNodeAddress" >>  "$SeedNodeFile"
    done

    ### Load SeedNodeFile in Memory & Remove SeedNodeFile
    declare -a SeedNodeList=()
    while read Line; do
        SeedNodeList+=($Line)
    done < $SeedNodeFile
    rm -f $SeedNodeFile

    ### Get highest Height from 5 random seed nodes
    SeedNodeCount=${#SeedNodeList[@]}
    for (( TopHeight=0, i=1; i<=5; i++ )); do
        RandomOffset=$(( RANDOM % $SeedNodeCount ))
        SeedNodeUri="http://${SeedNodeList[$RandomOffset]}/api/loader/status/sync"
        SeedNodeHeight=$( curl --max-time 2 -s $SeedNodeUri | jq -r '.height' )
        if [ "$SeedNodeHeight" -gt "$TopHeight" ]; then TopHeight=$SeedNodeHeight; fi
    done

    ### Get local qredit-full-node height
    LocalHeight=$( curl --max-time 2 -s 'http://127.0.0.1:4101/api/loader/status/sync' | jq '.height' )

    ### Test qredit-node Sync.
    if [ "$LocalHeight" -eq "$TopHeight" ]; then

        ForeverPid=$( forever --plain list | grep $QreditNodePid | sed -nr 's/.*\[(.*)\].*/\1/p' )
        cd $QreditNodeDirectory

        ### Stop qredit-node
        forever --plain stop $ForeverPid > /dev/null 2>&1 &
        sleep 1

        ### Dump Database
        SnapshotFilename='qredit_'$QreditNetwork'_'$LocalHeight
        pg_dump -O "qredit_$QreditNetwork" -Fc -Z6 > "$SnapshotDirectory/$SnapshotFilename"
        sleep 1

        ### Start qredit-node
#       forever --plain start app.js --genesis "genesisBlock.$QreditNetwork.json" --config "config.$QreditNetwork.json" > /dev/null 2>&1 &
        forever --plain start app.js --genesis "genesisBlock.json" --config "config.json" > /dev/null 2>&1 &

        ### Update Symbolic Link
        rm -f "$SnapshotDirectory/current"
        ln -s "$SnapshotDirectory/$SnapshotFilename" "$SnapshotDirectory/current"
    fi
fi

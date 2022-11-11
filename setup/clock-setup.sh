#!/bin/bash

INTERFACE=$1
DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
pkill ptp4l
pkill phc2sys

gPTP_CONF="$DIR/ptp/gPTP_i225-1G.cfg"

if [[ -z $gPTP_CONF ]]; then
        echo "gPTP configuration file for I225 is missing"
        exit -1
fi

mkdir -p /tmp/dpdk
taskset -c 1 ptp4l -P2Hi $INTERFACE -f $gPTP_CONF --step_threshold=1 --socket_priority=0 -m &> /tmp/dpdk/ptp4l.log &

sleep 2

pmc -u -b 0 -t 1 "SET GRANDMASTER_SETTINGS_NP clockClass 248
        clockAccuracy 0xfe offsetScaledLogVariance 0xffff currentUtcOffset 37
        leap61 0 leap59 0 currentUtcOffsetValid 1 ptpTimescale 1 timeTraceable
        1 frequencyTraceable 0 timeSource 0xa0" &> /tmp/dpdk/pmc.log

sleep 3

taskset -c 1 phc2sys -s $INTERFACE -c CLOCK_REALTIME --step_threshold=1 \
        --transportSpecific=1 -O 0 -w -ml 7 &> /tmp/dpdk/phc2sys.log &

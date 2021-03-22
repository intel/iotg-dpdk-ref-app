#!/bin/bash

IFACE=$1

if [[ -z $IFACE ]]; then
        echo "Usage: $0 [i225/i219]"
        exit -1
fi

if [[ $IFACE == "i225" ]]; then
        INTERFACE="enp169s0"
        MAC="00:a0:c9:00:00:01"

elif [[ $IFACE == "i219" ]]; then
        INTERFACE="enp0s31f6"
        MAC="00:a0:c9:00:00:13"
fi

pkill ptp4l
pkill phc2sys

# set MAC address
ip link set $INTERFACE down
ip link set $INTERFACE address $MAC
ip link set $INTERFACE up

gPTP_CONF="/home/cbrd/dpdk/i225_config/gPTP_i225-1G.cfg"

if [[ -z $gPTP_CONF ]]; then
	echo "gPTP configuration file for I225 is missing"
	exit -1
fi

taskset -c 1 ptp4l -P2Hi $INTERFACE -f $gPTP_CONF --step_threshold=1 --socket_priority=0 -m &> /var/log/ptp4l.log &

sleep 2

pmc -u -b 0 -t 1 "SET GRANDMASTER_SETTINGS_NP clockClass 248
        clockAccuracy 0xfe offsetScaledLogVariance 0xffff currentUtcOffset 37
        leap61 0 leap59 0 currentUtcOffsetValid 1 ptpTimescale 1 timeTraceable
        1 frequencyTraceable 0 timeSource 0xa0" &> /var/log/pmc.log

sleep 3

taskset -c 1 phc2sys -s $INTERFACE -c CLOCK_REALTIME --step_threshold=1 \
	--transportSpecific=1 -O 0 -w -ml 7 &> /var/log/phc2sys.log &

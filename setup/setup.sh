#!/bin/bash

IFACE=$1
MODE=$2
PLAT=$3
BOARD=$4

DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PLAT_CONFIG=""
CONFIG_DIR="$DIR/config"

function init_interface()
{
	# Always remove previous qdiscs
	tc qdisc del dev $IFACE parent root 2> /dev/null
	tc qdisc del dev $IFACE parent ffff: 2> /dev/null
	tc qdisc add dev $IFACE ingress

	# Set an even queue pair. Minimum is 4 rx 4 tx
	#if i225
	ethtool -L $IFACE combined $TX_Q_COUNT
	RXQ_COUNT=$(ethtool -l $IFACE | sed -e '1,/^Current/d' | grep -i Combined | awk '{print $2}')
	TXQ_COUNT=$RXQ_COUNT

	# Restart interface and systemd, also set HW MAC address for multicast
	ip link set $IFACE down
	systemctl restart systemd-networkd.service
	ip link set dev $IFACE address $IFACE_MAC_ADDR
	ip link set dev $IFACE up
	sleep 3

	# Provide static ip address for interfaces
	ip addr flush dev $IFACE
	ip addr add $IFACE_IP_ADDR/24 brd $IFACE_BRC_ADDR dev $IFACE

	# Flush neighbours, just in case
	ip neigh flush all dev $IFACE
	#ip neigh flush all dev $IFACE.vlan

	# Turn off VLAN Stripping
	if [ "$VLAN_STRIP_SUPPORT" = "YES" ]; then
		echo "Turning off vlan stripping"
		ethtool -K $IFACE rxvlan off
	fi

	# Disable EEE option is set in config file
	if [ "$EEE_TURNOFF" = "YES" ]; then
		echo "Turning off EEE"
		ethtool --set-eee $IFACE eee off &> /dev/null
	fi

}

set_irq()
{
	# Set irq affinity
	#set_irq_smp_affinity $IFACE $DIR/../common/$IRQ_AFFINITY_FILE

	AFFINITY_FILE=$IRQ_AFFINITY_FILE
	if [ -z $AFFINITY_FILE ]; then
		echo "Error: AFFINITY_FILE not defined"; exit 1;
	fi
	echo "Setting IRQ affinity based on $AFFINITY_FILE"

	#TODO: DPDK app already use core 0 and 1. Need to change core number on $AFFINITY_FILE
	while IFS=, read -r CSV_Q CSV_CORE CSV_COMMENTS; do
		IRQ_NUM=$(cat /proc/interrupts | grep $IFACE.*$CSV_Q | awk '{print $1}' | tr -d ":")
		echo "Echo-ing 0x$CSV_CORE > /proc/irq/$IRQ_NUM/smp_affinity --> $IFACE:$CSV_Q "
		if [ -z $IRQ_NUM ]; then
			echo "Error: invalid IRQ NUM"; exit 1;
		fi

		echo $CSV_CORE > /proc/irq/$IRQ_NUM/smp_affinity
	done < $AFFINITY_FILE
}

setup_mqprio()
{
	#setup_mqprio $IFACE
	MQPRIO_ARR=$MQPRIO_MAP
	NUM_TC=$(printf "%s\n" ${MQPRIO_ARR[@]} | sort | tail -n 1)

	for i in $(seq 0 $NUM_TC); do
		QUEUE_OFFSETS="$QUEUE_OFFSETS 1@$i"
	done

	NUM_TC=$(expr $NUM_TC + 1)

	CMD=$(echo "tc qdisc replace dev $IFACE parent root handle 100 mqprio" \
					" num_tc $NUM_TC map $MQPRIO_MAP queues $QUEUE_OFFSETS" \
					" hw 0")

	echo "Run: $CMD"; $CMD;
	sleep 10
}

setup_taprio()
{
	#setup_taprio    $IFACE
	# # To use replace, we need a base for the first time. Also, we want to
	# # ensure no packets are "stuck" in a particular queue if TAPRIO completely
	# # closes it off.

	TAPRIO_ARR=$TAPRIO_MAP
	NUM_TC=$(printf "%s\n" ${TAPRIO_ARR[@]} | sort | tail -n 1)

	for i in $(seq 0 $NUM_TC); do
		QUEUE_OFFSETS="$QUEUE_OFFSETS 1@$i"
	done

	NUM_TC=$(expr $NUM_TC + 1)

	# i225 does not support basetime in the future
	if [[ $PLAT == i225* ]]; then
		BASE=$(date +%s%N)
	else
		BASE=$(expr $(date +%s) + 5)000000000
	fi

	CMD=$(echo "tc qdisc replace dev $IFACE parent root handle 100 taprio" \
					"num_tc $NUM_TC map $TAPRIO_MAP" \
					"queues $QUEUE_OFFSETS " \
					"base-time $BASE" \
					"$TAPRIO_SCHED" \
					"$TAPRIO_FLAGS")

	echo "Run: $CMD"; $CMD;
	sleep 10
}

setup_etf()
{
	#setup_etf $IFACE
	#TODO: Supports specifying 1ETF Q per port only,
	#      add a for loop and array if need more

	if [[ -z $ETF_Q  || -z $ETF_DELTA ]]; then
		echo "Error: ETF_q or ETF_DELTA not specified"; exit 1;
	fi

	NORMAL_QUEUE=$(expr $ETF_Q + 1) #TC qdisc id start from 1 instead of 0

	#ETF qdisc
	HANDLE_ID="$( tc qdisc show dev $IFACE | tr -d ':' | awk 'NR==1{print $3}' )"

	# The ETF_DELTA dont really apply to AF_XDP.

	CMD=$(echo "tc qdisc replace dev $IFACE parent $HANDLE_ID:$NORMAL_QUEUE etf" \
					" clockid CLOCK_TAI delta $ETF_DELTA offload")

	echo "Run: $CMD"; $CMD;
	sleep 10
}

set_rule()
{
	RULES31=$(ethtool -n $IFACE | grep "Filter: 31")
	if [ ! -z "$RULES31" ]; then
			echo "Deleting filter rule 31"
			ethtool -N $IFACE delete 31
	fi
	RULES30=$(ethtool -n $IFACE | grep "Filter: 30")
	if [ ! -z "$RULES30" ]; then
			echo "Deleting filter rule 30"
			ethtool -N $IFACE delete 30
	fi
	RULES29=$(ethtool -n $IFACE | grep "Filter: 29")
	if [ ! -z "$RULES29" ]; then
			echo "Deleting filter rule 29"
			ethtool -N $IFACE delete 29
	fi

	# Use flow-type to push ptp packet to $PTP_RX_Q
        ethtool -N $IFACE flow-type ether proto 0x88f7 queue $PTP_RX_Q
        echo "Adding flow-type for ptp packet to q-$PTP_RX_Q"

	# Use flow-type to push DPDK reference app packet packet to $RX_PKT_Q
	ethtool -N $IFACE flow-type ether vlan 24576 vlan-mask 0x1FFF action $RX_PKT_Q
	echo "Adding flow-type for DPDK reference app with VLAN packet to q-$RX_PKT_Q"

	# Use flow-type to push DPDK reference app with standard IEEE802.3 packet to 0
	ethtool -N $IFACE flow-type ether proto 0x0800 queue 0
	echo "Adding flow-type for DPDK reference app with standard IEEE802.3 packet to q-0"
}

usage()
{
	echo "Usage: $0"
	echo "  \$ $0 <interface> <talker/listener> <platform> <board>"
	echo "  interface,          Network interface"
	echo "  talker/listener,    Choose either talker or listener"
	echo "  platform,           Currently only support i225"
	echo "  board,              Currently only support icx, tgl"
	echo
	echo "  Example,"
	echo "  $0 enp169s0 talker i225 tgl"
}

main()
{
	if [[ -z $IFACE || -z $MODE || -z $PLAT || -z $BOARD ]]; then
		echo "Error: Missing argument"
		usage
		exit 1
	fi

	if [[ $PLAT == "i225" ]]; then
		if [[ $MODE == "listener" ]]; then
			PLAT_CONFIG="i225-rx.config"

		elif [[ $MODE == "talker" ]]; then
			PLAT_CONFIG="i225-tx.config"

		else
			echo Error: Invalid argument $MODE
			exit 1
		fi
		echo sourcing $PLAT_CONFIG
		source $CONFIG_DIR/$PLAT_CONFIG
		echo Read variable iface mac addr=$IFACE_MAC_ADDR

	else
		echo Error: Invalid platform $PLAT. Only i225 is supported.
		exit 1
	fi

        init_interface $IFACE

	if [[ $MODE == "listener" ]]; then
		if [[ "$BOARD" == "icx" ]]; then
			setup_mqprio $IFACE
		fi

	elif [[ $MODE == "talker" ]]; then
		if [[ $BOARD == "icx" ]]; then
			setup_taprio $IFACE
			setup_etf $IFACE
		fi
        fi

	set_rule $IFACE


        sleep 10
        c=1
        while [ $c -lt 3 ]; do
            ./setup/clock-setup.sh $IFACE

            sleep 30 #Give some time for clock daemons to start.
            msg=`tail -n 1 /var/log/ptp4l.log | grep -E '(master|role)'`
            if [[ ! -z $msg ]]; then
                echo assume as master clock
                break
            fi

            msg=`tail -n 1 /var/log/ptp4l.log | awk '{ print $3 }'`
            re='^[0-9]+$'
            if  [[ $msg =~ $re ]]; then
                if [ $msg -lt 100 ]; then
                    echo time is sync
                    break
                else
                    echo time is NOT sync
                fi
            fi
            ((c++))
        done
        echo Done
}

main
exit 0

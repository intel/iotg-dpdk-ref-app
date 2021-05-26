#!/bin/sh

# configure TSN environment

IFACE="enp169s0"
PLAT="i225"
DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

#source $DIR/helpers.sh
#source $DIR/$PLAT/$CONFIG.config

IFACE_MAC_ADDR="aa:00:aa:00:aa:00"
IFACE_IP_ADDR="169.254.1.11"
IFACE_BRC_ADDR="169.254.1.255"
IFACE_VLAN_IP_ADDR="169.254.11.11"
IFACE_VLAN_BRC_ADDR="169.254.11.255"
IFACE_VLAN_ID="3"
TX_Q_COUNT=4
RX_Q_COUNT=4
VLAN_PRIORITY_SUPPORT="NO"
VLAN_STRIP_SUPPORT="NO"
EEE_TURNOFF="NO"
IRQ_AFFINITY_FILE="irq_affinity_4c_4TxRx.map"
TAPRIO_MAP="0 1 2 3 0 0 0 0 0 0 0 0 0 0 0 0"
TAPRIO_SCHED=("sched-entry S 01 100000"
              "sched-entry S 0E 400000")
TAPRIO_FLAGS="flags 0x2"
PTP_IFACE_APPEND=".vlan"
PTP_PHY_HW="i225-1G"
PTP_TX_Q=2
PTP_RX_Q=2
ETF_Q=3
ETF_DELTA=700000
#ETF_FLAGS="deadline_mode off skip_sock_check off"
TARGET_IP_ADDR="169.254.1.22"
TX_PKT_Q=3
RX_PKT_Q=3
TX_XDP_Q=1 # AF-XDP is not available (NA) yet, this is a placeholder
RX_XDP_Q=1
TXTIME_OFFSET=20000
NUMPKTS=1000000
SIZE=64
INTERVAL=1000000
EARLY_OFFSET=700000
XDP_MODE="NA" # AF-XDP is not available (NA) yet
XDP_INTERVAL=200000
XDP_EARLY_OFFSET=100000


#init_interface $IFACE

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

# Set VLAN ID to 3, all traffic fixed to one VLAN ID, but vary the VLAN Priority
#ip link delete dev $IFACE.vlan 2> /dev/null
#ip link add link $IFACE name $IFACE.vlan type vlan id $IFACE_VLAN_ID

# Provide static ip address for interfaces
ip addr flush dev $IFACE
#ip addr flush dev $IFACE.vlan
ip addr add $IFACE_IP_ADDR/24 brd $IFACE_BRC_ADDR dev $IFACE
#ip addr add $IFACE_VLAN_IP_ADDR/24 brd $IFACE_VLAN_BRC_ADDR dev $IFACE.vlan

# Map socket priority N to VLAN priority N
if [[ "$VLAN_PRIORITY_SUPPORT" == "YES" ]]; then
    echo "Mapping socket priority N to VLAN priority N for $IFACE"
    ip link set $IFACE.vlan type vlan egress-qos-map 1:1
    ip link set $IFACE.vlan type vlan egress-qos-map 2:2
    ip link set $IFACE.vlan type vlan egress-qos-map 3:3
    ip link set $IFACE.vlan type vlan egress-qos-map 4:4
    ip link set $IFACE.vlan type vlan egress-qos-map 5:5
    ip link set $IFACE.vlan type vlan egress-qos-map 6:6
    ip link set $IFACE.vlan type vlan egress-qos-map 7:7
fi

# Flush neighbours, just in case
ip neigh flush all dev $IFACE
#ip neigh flush all dev $IFACE.vlan

# Turn off VLAN Stripping
if [[ "$VLAN_STRIP_SUPPORT" == "YES" ]]; then
    echo "Turning off vlan stripping"
    ethtool -K $IFACE rxvlan off
fi

# Disable EEE option is set in config file
if [[ "$EEE_TURNOFF" == "YES" ]]; then
    echo "Turning off EEE"
    ethtool --set-eee $IFACE eee off &> /dev/null
fi

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

#setup_taprio    $IFACE
# # To use replace, we need a base for the first time. Also, we want to
# # ensure no packets are "stuck" in a particular queue if TAPRIO completely
# # closes it off.
# # This command is does nothing if used when there's an existing qdisc.
tc qdisc add dev $IFACE root mqprio \
    num_tc 1 map 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 \
    queues 1@0 hw 0 &> /dev/null

sleep 5
#Count
TAPRIO_ARR=($TAPRIO_MAP)
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
                "${TAPRIO_SCHED[@]}" \
                "$TAPRIO_FLAGS")

echo "Run: $CMD"; $CMD;
sleep 10

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
                " clockid CLOCK_TAI delta $ETF_DELTA offload" \
                " $ETF_FLAGS") #deadline_mode off skip_sock_mode off

echo "Run: $CMD"; $CMD;
sleep 10

RULES31=$(ethtool -n enp169s0 | grep "Filter: 31")
if [[ ! -z $RULES31 ]]; then
    echo "Deleting existing filter rule 31"
    ethtool -N enp169s0 delete 31
fi
RULES30=$(ethtool -n enp169s0 | grep "Filter: 30")
if [[ ! -z $RULES30 ]]; then
    echo "Deleting existing filter rule 30"
    ethtool -N enp169s0 delete 30
fi
# Use flow-type to push ptp packet to $PTP_RX_Q
ethtool -N $IFACE flow-type ether proto 0x88f7 queue $PTP_RX_Q
echo "Adding flow-type filter for ptp packet to q-$PTP_RX_Q"

## adding my own rule
# push iperf packet to queue 0
#ethtool -N $IFACE flow-type ether proto 0x0800 queue 0
#echo "Adding flow-type filter for iperf packet to q-0"
sleep 10

./clock-setup.sh $IFACE

sleep 30 #Give some time for clock daemons to start.

exit 0

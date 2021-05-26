#!/bin/sh

IFACE="enp169s0"
PLAT="i225"
DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

#source $DIR/helpers.sh
#source $DIR/$PLAT/$CONFIG.config

IFACE_MAC_ADDR="22:bb:22:bb:22:bb"
IFACE_IP_ADDR="169.254.1.22"
IFACE_BRC_ADDR="169.254.1.255"
IFACE_VLAN_IP_ADDR="169.254.11.22"
IFACE_VLAN_BRC_ADDR="169.254.11.255"
IFACE_VLAN_ID="3"
TX_Q_COUNT=4
RX_Q_COUNT=4
VLAN_PRIORITY_SUPPORT="YES"
VLAN_STRIP_SUPPORT="NO"
EEE_TURNOFF="NO"
IRQ_AFFINITY_FILE="irq_affinity_4c_4TxRx.map"
MQPRIO_MAP="0 1 2 3 0 0 0 0 0 0 0 0 0 0 0 0"
PTP_IFACE_APPEND=".vlan"
PTP_PHY_HW="i225-1G"
PTP_TX_Q=2
PTP_RX_Q=2
TX_PKT_Q=3
RX_PKT_Q=3
TX_XDP_Q=1
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
ip link delete dev $IFACE.vlan 2> /dev/null
ip link add link $IFACE name $IFACE.vlan type vlan id $IFACE_VLAN_ID

# Provide static ip address for interfaces
ip addr flush dev $IFACE
ip addr flush dev $IFACE.vlan
ip addr add $IFACE_IP_ADDR/24 brd $IFACE_BRC_ADDR dev $IFACE
ip addr add $IFACE_VLAN_IP_ADDR/24 brd $IFACE_VLAN_BRC_ADDR dev $IFACE.vlan

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
ip neigh flush all dev $IFACE.vlan

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

#setup_mqprio $IFACE
#Count
MQPRIO_ARR=($MQPRIO_MAP)
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

RULES31=$(ethtool -n enp169s0 | grep "Filter: 31")
if [[ ! -z $RULES31 ]]; then
    echo "Deleting filter rule 31"
    ethtool -N enp169s0 delete 31
fi
RULES30=$(ethtool -n enp169s0 | grep "Filter: 30")
if [[ ! -z $RULES30 ]]; then
    echo "Deleting filter rule 30"
    ethtool -N enp169s0 delete 30
fi
RULES29=$(ethtool -n enp169s0 | grep "Filter: 29")
if [[ ! -z $RULES30 ]]; then
    echo "Deleting filter rule 29"
    ethtool -N enp169s0 delete 29
fi

# Use flow-type to push ptp packet to $PTP_RX_Q
ethtool -N $IFACE flow-type ether proto 0x88f7 queue $PTP_RX_Q
echo "Adding flow-type for ptp packet to q-$PTP_RX_Q"

# Use flow-type to push txrx-tsn packet packet to $RX_PKT_Q
ethtool -N $IFACE flow-type ether vlan 24576 vlan-mask 0x1FFF action $RX_PKT_Q

# use flow-type to push DPDK app to $RX_PKT_Q
#VLAN_PROTO="0x8100"
#PROTO="0xe003"

#ethtool -N $IFACE flow-type ether proto $PROTO queue $RX_PKT_Q
echo "Adding flow-type for DPDK packet to q-$RX_PKT_Q"

# Use flow-type to push iperf3 packet to 0
ethtool -N $IFACE flow-type ether proto 0x0800 queue 0
echo "Adding flow-type for iperf3 packet to q-0"
sleep 10

./clock-setup.sh $IFACE
sleep 30 #Give some time for clock daemons to start.

exit 0

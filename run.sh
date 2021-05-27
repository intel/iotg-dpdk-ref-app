#!/bin/sh

MOUNT_DIR="/dev/hugepages"
APP_COMPONENT=""

PORTMASK="0x1"
LCOREQ=1
OUTPUTFILE="default_listenerOPfile.csv"
DEBUG=0
TIME_PERIOD=300
DEST_MACADDR="00:A0:C9:00:00:02"
SEND_PKTCNT=150000

green=$(tput setaf 2)
normal=$(tput sgr0)

show_usage (){
    printf "Usage: $0 [options [parameters]]\n"
    printf "\n"
    printf "Usage: ./run.sh <PLAT> <IFACE> [ACTION] [APP-COMPONENT] <Options>\n"
    printf "Usage Example: ./run.sh tgl enp169s0 run listener -D 1\n"
    printf "<PLAT>: Example: tgl, i225 etc \n"
    printf " <IFACE>: Example: enp169s0 \n"
    printf "[ACTION]: setup,init or run \n"
    printf "[APP-COMPONENT]: listener, talker\n"
    printf "<Options>: are specified below and vary for listener and talker applications\n"
    printf "\n"
    printf "${green}Listener Options:${normal}\n"
    printf " -p|--portmask: hexadecimal bitmask of ports to configure\n"
    printf " -q|--lcoreq: NQ: number of queue (=ports) per lcore (default is 1)\n"
    printf " -f|--filename: LATENCY OUTPUT FILENAME: length should be less than 30 characters, preferably with .csv extension. Default is 'default_listenerOPfile.csv' if option not provided\n"
    printf " -D|--debug: 1 to enable debug mode, 0 default disable debug mode\n"
    printf " -h|--help, Print help\n"
    printf "${green}Talker Options:${normal}\n"
    printf " -p|--portmask: hexadecimal bitmask of ports to configure\n"
    printf " -q|--lcoreq: NQ: number of queue (=ports) per lcore (default is 1)\n"
    printf " -D|--debug: 1 to enable debug mode, 0 default disable debug mode\n"
    printf " -T|--tperiod: Packet will be transmit each PERIOD microseconds (must >=50us, 50us by default, 5000000 max)\n"
    printf " -d|--destmac: Destination MAC address: use ':' format, for example, 08:00:27:cf:69:3e\n"
    printf " -c|--pktcnt: Total packet to be send to destination (100000 by default, must not >1500000)\n"
    printf " -h|--help, Print help\n"

return 0
}


main() {
    #if [ $USER != "root" ]; then
    #    echo "Please run as root"
    #    exit
    #fi

    # Check for minimum inputs
    if [ "$1" = "--help" -o $# -lt 3 ]; then
        show_usage
        exit 1
    fi

    PLAT=$1
    IFACE=$2
    ACTION=$3
    APP_COMPONENT=$4


    # Check for <PLAT>
    if [ "$1" = "tgl" -o "$1" = "i225" ]; then
        echo "Platform is $1"
    elif [ "$1" = "ehl" -o "$1" = "tglh" -o "$1" = "adl" -o "$1" = "tglh2" -o "$1" = "ehl2" -o "$1" = "adl2" ]; then
        echo -e "Warning: This application is verified on Tgl platform.\n" \
                "This application works irrespective of platforms and depends on NIC \n" \
                "Please report if you see any issues with other platforms";
    else
        echo -e "Run.sh invaliid <PLAT>:"
        exit 1
    fi

    # Check for valid <IFACE>
    ip a show $IFACE up > /dev/null
    if [ $? -eq 1 ]; then echo "Error: Invalid interface $IFACE"; exit 1; fi

    # Only for debug: timesync per-run logging
    #if [[ "$RUNSH_DEBUG_MODE" == "YES" && "$ACTION" == "run" ]]; then
       # ts_log_start
    #fi

    # Execute: redirect to opcua if opcua config, otherwise execute shell scripts
    if [ "$ACTION" = "setup" -o "$ACTION" = "init" ]; then
        ethtool -T  $IFACE | grep "PTP Hardware Clock: 0"
        if [ $? -eq 1 ];
        then
            echo "NIC does not support PTP feature, so ptp time_sync is not executed and we will not get appropriate latency from the below listener app"
            exit 1
        else
            if [ -d $MOUNT_DIR ]
            then
                echo "Directory already exists"
            else
                mkdir $MOUNT_DIR
            fi
	    echo "Mounting hugepages"
            mountpoint -q /dev/hugepages || mount -t hugetlbfs nodev /dev/hugepages
            echo 256 > /sys/devices/system/node/node0/hugepages/hugepages-2048kB/nr_hugepages
            if [ "$APP_COMPONENT" = "listener" ]
            then
                echo "Executing setup-vs1b.sh script"
                ./setup/setup-vs1b.sh
		echo "Compiling Listener app"
                cd listener
                make static
                cd ..
            else
                echo "Executing setup-vs1a.sh script"
                ./setup/setup-vs1a.sh
		echo "Compiling Talker app"
                cd talker
                make static
                cd ..
            fi
        fi

    elif [ "$ACTION" = "run" ]; then
        ethtool -K $IFACE ntuple on
        ethtool -N $IFACE flow-type ether vlan 24576 vlan-mask 0x1FFF action 3
        if [ "$APP_COMPONENT" = "listener" ]; then
            while [ ! -z "$5" ]; do
                case "$5" in
                    --portmask|-p)
                        shift
                        PORTMASK=$5
                        ;;
                    --lcoreq|-q)
                        shift
                        LCOREQ=$5
                        ;;
                    --filename|-f)
                        shift
                        OUTPUTFILE=$5
                        ;;
                    --debug|-D)
                        shift
                        DEBUG=$5
                        ;;
                    *)
                        show_usage
                        exit 1;
                        ;;
                esac
                shift
            done
            ./listener/build/listener -l 2-3 -n 1 --vdev=net_af_xdp0,iface=$IFACE,start_queue=3 -- -p $PORTMASK -q $LCOREQ -f $OUTPUTFILE -D $DEBUG
        elif [ "$APP_COMPONENT" = "talker" ]; then
            while [ ! -z "$5" ]; do
                case "$5" in
                    --portmask|-p)
                        shift
                        PORTMASK=$5
                        ;;
                    --lcoreq|-q)
                        shift
                        LCOREQ=$5
                        ;;
                    --tperiod|-T)
                        shift
                        TIME_PERIOD=$5
                        ;;
                    --destmac|-d)
                        shift
                        DEST_MACADDR=$5
                        ;;
                    --pktcnt|-c)
                        shift
                        SEND_PKTCNT=$5
                        ;;
                    --debug|-D)
                        shift
                        DEBUG=$5
                        ;;
                    *)
                        show_usage
                        exit 1;
                        ;;
                esac
                shift
            done
            ./talker/build/talker -l 3 -n 1 --vdev=net_af_xdp0,iface=$IFACE -- -p $PORTMASK -q $LCOREQ -T $TIME_PERIOD -d $DEST_MACADDR -c $SEND_PKTCNT -D $DEBUG
        else
            show_usage
            exit 1
        fi
    else
        echo "Error: run.sh invalid commands. Please run ./run.sh --help for more info."
        exit 1
    fi
}

main "$@"

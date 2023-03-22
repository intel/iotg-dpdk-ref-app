#!/bin/bash

DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
MOUNT_DIR="/dev/hugepages"
APP_COMPONENT=""

HUGEPAGES=2048
PORTMASK="0x1"
LCOREQ=1
OUTPUTFILE1="listener1.csv"
OUTPUTFILE2="listener2.csv"
DEBUG=0
TIME_PERIOD=3000
DEST_MACADDR="22:bb:22:bb:22:bb"
SEND_PKTCNT=100000
MODE="Single"

SETUP_DIR=$DIR/setup

green=$(tput setaf 2)
normal=$(tput sgr0)

show_usage (){
    printf "Usage: $0 [options [parameters]]\n"
    printf "\n"
    printf "Usage: ./run.sh <PLAT> <BOARD> <IFACE> [ACTION] [APP-COMPONENT] [MODE] <Options>\n\n"
    printf "Usage Example: ./run.sh i225 tgl enp169s0 run listener single -D 1\n"
    printf "<PLAT>: Network Interface Card. Example: i225 etc \n"
    printf "<BOARD>: Example: icx, tglu \n"
    printf "<IFACE>: Netork interface. Example: enp169s0 \n"
    printf "[ACTION]: setup or run \n"
    printf "[APP-COMPONENT]: listener, talker\n"
    printf "[MODE]: single, dual, mix\n"
    printf "        In single mode, only 1 talker and listener apps are running via AF_XDP socket.\n"
    printf "        In dual mode, 2 talker and 2 listener apps are running via AF_XDP socket.\n"
    printf "        In mix mode, 2 talker and 2 listener apps are running. Each talker and listener \n"
    printf "        running via AF_XDP and AF_PACKET respectively. \n"
    printf "<Options>: are specified below and vary for listener and talker applications\n"
    printf "\n"
    printf "${green}Listener Options:${normal}\n"
    printf " -p|--portmask: hexadecimal bitmask of ports to configure. Default is $PORTMASK\n"
    printf " -q|--lcoreq: NQ: number of queue (=ports) per lcore (default is $LCOREQ)\n"
    printf " -f|--filename: LATENCY OUTPUT FILENAME: length should be less than 30 characters, preferably with .csv extension. Default is '$OUTPUTFILE1' if option not provided\n"
    printf " -D|--debug: 1 to enable debug mode, $DEBUG default disable debug mode\n"
    printf " -h|--help, Print help\n"
    printf "${green}Talker Options:${normal}\n"
    printf " -p|--portmask: hexadecimal bitmask of ports to configure. Default is $PORTMASK\n"
    printf " -q|--lcoreq: NQ: number of queue (=ports) per lcore (default is $LCOREQ)\n"
    printf " -D|--debug: 1 to enable debug mode, $DEBUG default disable debug mode\n"
    printf " -T|--tperiod: Packet will be transmit each PERIOD microseconds (must >=300us, $TIME_PERIODus by default, 5000000 max)\n"
    printf " -d|--destmac: Destination MAC address: use ':' format, default is $DEST_MACADDR\n"
    printf " -c|--pktcnt: Total packet to be send to destination ($SEND_PKTCNT by default, max 2000000)\n"
    printf " -h|--help, Print help\n"

return 0
}

# trap ctrl+c and call generate_plot()
trap generate_plot INT
function generate_plot()
{
    if [ $APP_COMPONENT = "listener" ]; then
        for outfile in $OUTPUTFILE1 $OUTPUTFILE2; do
            if [ -f $outfile ]; then
                plot=${outfile%.csv}.png
	        echo "Generate plot for $outfile -> $plot"
                gnuplot -e "set output '$plot'; FILENAME='$outfile'" $SETUP_DIR/plot-latency.gnu -p
                echo Results stored in $dt/$outfile
                mv $outfile $dt/
                mv $plot $dt/
            fi
	done
    fi
    echo Exit app
}

main() {
    # Check for minimum inputs
    if [ "$1" = "--help" -o $# -lt 3 ]; then
        show_usage
        exit 1
    fi

    PLAT=$1
    BOARD=$2
    IFACE=$3
    ACTION=$4
    APP_COMPONENT=$5
    MODE=$6

    dt=$(date '+%d%m%Y%H%M%S');
    dt="results/$dt"
    mkdir -p $dt

    # Check for <BOARD>
    if [ "$2" = "icx" -o "$2" = "tgl" ]; then
        echo "Platform is $2"
    elif [ "$2" = "ehl" -o "$2" = "tglh" -o "$2" = "adl" -o "$2" = "tglh2" -o "$2" = "ehl2" -o "$2" = "adl2" -o "$2" = "rpl" ]; then
        echo -e "Warning: This application is verified on Tgl-U platform.\n" \
                "This application works irrespective of platforms and depends on NIC \n" \
                "Please report if you see any issues with other platforms";
    else
        echo -e "Run.sh invalid <BOARD>:"
        exit 1
    fi

    if [ "$MODE" = "single" -o "$MODE" = "dual" -o "$MODE" = "mix" ]; then
	echo "Spawn Mode is $6"
    else
	echo -e "Run.sh invalid <MODE>: $MODE. Run as single mode."
	MODE="single"
    fi

    # Check for valid <IFACE>
    ip a show $IFACE up > /dev/null
    if [ $? -eq 1 ]; then echo "Error: Invalid interface $IFACE"; exit 1; fi

    if [ "$ACTION" = "setup" ]; then
        ethtool -T  $IFACE | grep -E '(hardware-transmit|software-transmit)'
        if [ $? -eq 1 ];
        then
            echo "NIC does not support PTP feature. The DPDK reference application will not be executed."
            exit 1
        else
            if [ ! -d $MOUNT_DIR ]
            then
                mkdir $MOUNT_DIR
            fi
	    echo "Mounting hugepages"
            mountpoint -q $MOUNT_DIR || mount -t hugetlbfs nodev $MOUNT_DIR
            echo $HUGEPAGES > /sys/devices/system/node/node0/hugepages/hugepages-2048kB/nr_hugepages
            ethtool -K $IFACE ntuple on

            if [ "$APP_COMPONENT" = "listener" ]; then
		echo "Compiling Listener app"
                make -C listener clean
                make -C listener

            elif [ "$APP_COMPONENT" = "talker" ]; then
		echo "Compiling Talker app"
                make -C talker clean
                make -C talker

            else
                echo "Error: Invalid argument $APP_COMPONENT"
                exit 1
            fi

            echo "Configure network interface $IFACE as $APP_COMPONENT"
            ./setup/setup.sh $IFACE $APP_COMPONENT $PLAT $BOARD
        fi

    elif [ "$ACTION" = "run" ]; then
        if [ "$APP_COMPONENT" = "listener" ]; then
            while [ ! -z "$7" ]; do
                case "$7" in
                    --portmask|-p)
                        shift
                        PORTMASK=$7
                        ;;
                    --lcoreq|-q)
                        shift
                        LCOREQ=$7
                        ;;
                    --filename|-f)
                        shift
                        OUTPUTFILE1=$7
                        ;;
                    --debug|-D)
                        shift
                        DEBUG=$7
                        ;;
                    *)
                        show_usage
			shift
                        exit 1;
                        ;;
                esac
                shift
            done
	    if [ "$MODE" = "single" ]; then
                OUTPUTFILE1=af-xdp-single-$OUTPUTFILE1
                ./listener/build/listener -l 2 -n 1 --vdev=net_af_xdp0,iface=$IFACE,start_queue=0 -- -p $PORTMASK -q $LCOREQ -f $OUTPUTFILE1 -D $DEBUG
	    elif [ "$MODE" = "dual" ]; then
                OUTPUTFILE1=af-xdp-dual-$OUTPUTFILE1
                OUTPUTFILE2=af-xdp-dual-$OUTPUTFILE2
                ./listener/build/listener -l 2 -n 1 --vdev=net_af_xdp0,iface=$IFACE,start_queue=0 --file-prefix="listener1" -- -p $PORTMASK -q $LCOREQ -f $OUTPUTFILE1 -D $DEBUG &
                ./listener/build/listener -l 3 -n 1 --vdev=net_af_xdp1,iface=$IFACE,start_queue=3 --file-prefix="listener2" -- -p $PORTMASK -q $LCOREQ -f $OUTPUTFILE2 -D $DEBUG
            elif [ "$MODE" = "mix" ]; then
                OUTPUTFILE1=af-xdp-mix-$OUTPUTFILE1
                OUTPUTFILE2=af-packet-mix-$OUTPUTFILE2
                ./listener/build/listener -l 2 -n 1 --vdev=net_af_xdp0,iface=$IFACE,start_queue=0 --file-prefix="listener1" -- -p $PORTMASK -q $LCOREQ -f $OUTPUTFILE1 -D $DEBUG &
                ./listener/build/listener -l 3 -n 1 --vdev=net_af_packet0,iface=$IFACE --file-prefix="listener2" -- -p $PORTMASK -q $LCOREQ -f $OUTPUTFILE2 -D $DEBUG
	    fi
        elif [ "$APP_COMPONENT" = "talker" ]; then
            while [ ! -z "$7" ]; do
                case "$7" in
                    --portmask|-p)
                        shift
                        PORTMASK=$7
                        ;;
                    --lcoreq|-q)
                        shift
                        LCOREQ=$7
                        ;;
                    --tperiod|-T)
                        shift
                        TIME_PERIOD=$7
                        ;;
                    --destmac|-d)
                        shift
                        DEST_MACADDR=$7
                        ;;
                    --pktcnt|-c)
                        shift
                        SEND_PKTCNT=$7
                        ;;
                    --debug|-D)
                        shift
                        DEBUG=$7
                        ;;
                    *)
                        show_usage
			shift
                        exit 1;
                        ;;
                esac
                shift
            done
	    if [ "$MODE" = "single" ]; then
                ./talker/build/talker -l 2 -n 1 --vdev=net_af_xdp0,iface=$IFACE,start_queue=0 -- -p $PORTMASK -q $LCOREQ -T $TIME_PERIOD -d $DEST_MACADDR -c $SEND_PKTCNT -D $DEBUG -v 1
            elif [ "$MODE" = "dual" ]; then
                ./talker/build/talker -l 2 -n 1 --vdev=net_af_xdp0,iface=$IFACE,start_queue=0 --file-prefix="talker1" -- -p $PORTMASK -q $LCOREQ -T $TIME_PERIOD -d $DEST_MACADDR -c $SEND_PKTCNT -D $DEBUG -v 0 &
                ./talker/build/talker -l 3 -n 1 --vdev=net_af_xdp1,iface=$IFACE,start_queue=3 --file-prefix="talker2" -- -p $PORTMASK -q $LCOREQ -T $TIME_PERIOD -d $DEST_MACADDR -c $SEND_PKTCNT -D $DEBUG -v 1
            elif [ "$MODE" = "mix" ]; then
                ./talker/build/talker -l 2 -n 1 --vdev=net_af_xdp0,iface=$IFACE,start_queue=0 --file-prefix="talker1" -- -p $PORTMASK -q $LCOREQ -T $TIME_PERIOD -d $DEST_MACADDR -c $SEND_PKTCNT -D $DEBUG -v 0 &
                ./talker/build/talker -l 3 -n 1 --vdev=net_af_packet0,iface=$IFACE            --file-prefix="talker2" -- -p $PORTMASK -q $LCOREQ -T $TIME_PERIOD -d $DEST_MACADDR -c $SEND_PKTCNT -D $DEBUG -v 1
            else
                echo -e "Run.sh invalid <MODE>:"
	    fi
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

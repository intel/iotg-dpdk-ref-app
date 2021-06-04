#!/bin/sh

DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
MOUNT_DIR="/dev/hugepages"
APP_COMPONENT=""

HUGEPAGES=2048
PORTMASK="0x1"
LCOREQ=1
OUTPUTFILE="default_listenerOPfile.csv"
DEBUG=0
TIME_PERIOD=3000
DEST_MACADDR="22:bb:22:bb:22:bb"
SEND_PKTCNT=100000

SETUP_DIR=$DIR/setup

green=$(tput setaf 2)
normal=$(tput sgr0)

show_usage (){
    printf "Usage: $0 [options [parameters]]\n"
    printf "\n"
    printf "Usage: ./run.sh <PLAT> <BOARD> <IFACE> [ACTION] [APP-COMPONENT] <Options>\n\n"
    printf "Usage Example: ./run.sh tgl enp169s0 run listener -D 1\n"
    printf "<PLAT>: Network Interface Card. Example: i225 etc \n"
    printf "<BOARD>: Example: icx, tglu \n"
    printf "<IFACE>: Netork interface. Example: enp169s0 \n"
    printf "[ACTION]: setup or run \n"
    printf "[APP-COMPONENT]: listener, talker\n"
    printf "<Options>: are specified below and vary for listener and talker applications\n"
    printf "\n"
    printf "${green}Listener Options:${normal}\n"
    printf " -p|--portmask: hexadecimal bitmask of ports to configure. Default is $PORTMASK\n"
    printf " -q|--lcoreq: NQ: number of queue (=ports) per lcore (default is $LCOREQ)\n"
    printf " -f|--filename: LATENCY OUTPUT FILENAME: length should be less than 30 characters, preferably with .csv extension. Default is '$OUTPUTFILE' if option not provided\n"
    printf " -D|--debug: 1 to enable debug mode, $DEBUG default disable debug mode\n"
    printf " -h|--help, Print help\n"
    printf "${green}Talker Options:${normal}\n"
    printf " -p|--portmask: hexadecimal bitmask of ports to configure. Default is $PORTMASK\n"
    printf " -q|--lcoreq: NQ: number of queue (=ports) per lcore (default is $LCOREQ)\n"
    printf " -D|--debug: 1 to enable debug mode, $DEBUG default disable debug mode\n"
    printf " -T|--tperiod: Packet will be transmit each PERIOD microseconds (must >=50us, $TIME_PERIODus by default, 5000000 max)\n"
    printf " -d|--destmac: Destination MAC address: use ':' format, default is $DEST_MACADDR\n"
    printf " -c|--pktcnt: Total packet to be send to destination ($SEND_PKTCNT by default, must not >1500000)\n"
    printf " -h|--help, Print help\n"

return 0
}

# trap ctrl+c and call generate_plot()
function generate_plot()
{
    if [ $APP_COMPONENT = "listener" ]; then
         echo Generate plot
         gnuplot -e "FILENAME='$OUTPUTFILE'" $SETUP_DIR/plot-latency.gnu -p
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


    # Check for <BOARD>
    if [ "$2" = "icx" -o "$2" = "tgl" ]; then
        echo "Platform is $2"
    elif [ "$1" = "ehl" -o "$2" = "tglh" -o "$2" = "adl" -o "$2" = "tglh2" -o "$2" = "ehl2" -o "$2" = "adl2" ]; then
        echo -e "Warning: This application is verified on Tgl-U platform.\n" \
                "This application works irrespective of platforms and depends on NIC \n" \
                "Please report if you see any issues with other platforms";
    else
        echo -e "Run.sh invalid <BOARD>:"
        exit 1
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
                make -C listener static

            elif [ "$APP_COMPONENT" = "talker" ]; then
		echo "Compiling Talker app"
                make -C talker clean
                make -C talker static

            else
                echo "Error: Invalid argument $APP_COMPONENT"
                exit 1
            fi

            echo "Configure network interface $IFACE as $APP_COMPONENT"
            ./setup/setup.sh $IFACE $APP_COMPONENT $PLAT $BOARD
        fi

    elif [ "$ACTION" = "run" ]; then
        if [ "$APP_COMPONENT" = "listener" ]; then
            while [ ! -z "$6" ]; do
                case "$6" in
                    --portmask|-p)
                        shift
                        PORTMASK=$6
                        ;;
                    --lcoreq|-q)
                        shift
                        LCOREQ=$6
                        ;;
                    --filename|-f)
                        shift
                        OUTPUTFILE=$6
                        ;;
                    --debug|-D)
                        shift
                        DEBUG=$6
                        ;;
                    *)
                        show_usage
			shift
                        exit 1;
                        ;;
                esac
                shift
            done
            ./listener/build/listener -l 3 -n 1 --vdev=net_af_xdp0,iface=$IFACE,start_queue=3 -- -p $PORTMASK -q $LCOREQ -f $OUTPUTFILE -D $DEBUG
        elif [ "$APP_COMPONENT" = "talker" ]; then
            while [ ! -z "$6" ]; do
                case "$6" in
                    --portmask|-p)
                        shift
                        PORTMASK=$6
                        ;;
                    --lcoreq|-q)
                        shift
                        LCOREQ=$6
                        ;;
                    --tperiod|-T)
                        shift
                        TIME_PERIOD=$6
                        ;;
                    --destmac|-d)
                        shift
                        DEST_MACADDR=$6
                        ;;
                    --pktcnt|-c)
                        shift
                        SEND_PKTCNT=$6
                        ;;
                    --debug|-D)
                        shift
                        DEBUG=$6
                        ;;
                    *)
                        show_usage
			shift
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

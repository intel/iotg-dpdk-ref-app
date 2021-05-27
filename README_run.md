Demo of TALKER/LISTENER App
==============================
This is an DPDK Application which has two components.
1. Talker: This transmits the packets
2. Listener: This Listens to the packets transmitted by talker.

This application needs to be executed on 2 boards.

Features:
=========
1. Latency Calculation: This provides the latency of the packet: This is the time from the packet being transmitted to received.
2. Provides and output file with latency graph

Usage:
======
All examples are run with 2 units of the same platform. Mind the notation
"[Board A or B]". The following steps assumes both platforms are connected
to each other via an Ethernet connection and user has a terminal open

./run.sh <PLAT> <IFACE> [ACTION] [APP-COMPONENT] <Options>

[Board A]: Listener app

Example for listener setup: ./run.sh tgl enp169s0 setup listener
Example for listener run: ./run.sh tgl enp169s0 run listener -f output.csv


Listener Options:
-----------------
-p|--portmask: hexadecimal bitmask of ports to configure
-q|--lcoreq: NQ: number of queue (=ports) per lcore (default is 1)
-f|--filename: LATENCY OUTPUT FILENAME: length should be less than 30 characters, preferably with .csv extension. Default is 'default_listenerOPfile.csv' if option not provided
-D|--debug: 1 to enable debug mode, 0 default disable debug mode
-h|--help, Print help

[Board B]: Talker app

Example for talker setup: ./run.sh tgl enp169s0 setup talker
Example for talker run: ./run.sh tgl enp169s0 run talker -T 500 -d 08:00:27:cf:69:3e -c 5000 -D 0

Talker Options:
---------------
-p|--portmask: hexadecimal bitmask of ports to configure
-q|--lcoreq: NQ: number of queue (=ports) per lcore (default is 1)
-D|--debug: 1 to enable debug mode, 0 default disable debug mode
-T|--tperiod: Packet will be transmit each PERIOD microseconds (must >=50us, 50us by default, 5000000 max)
-d|--destmac: Destination MAC address: use ':' format, for example, 08:00:27:cf:69:3e
-c|--pktcnt: Total packet to be send to destination (100000 by default, must not >1500000)
-h|--help, Print help

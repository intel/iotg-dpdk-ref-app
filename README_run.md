Demo of DPDK TALKER/LISTENER App via AF_XDP PMD  
===============================================
This is an DPDK Application which has two components.
1. Talker: This transmits the packets
2. Listener: This Listens to the packets transmitted by talker.

This application needs to be executed on 2 boards.

Features:
=========
1. Latency Calculation: This provides the latency of the packet: This is the time from the packet being transmitted to received.
2. Provides and output file with latency graph
3. We can spawn two listeners and two talkers on different queues.

Usage:   
All examples are run with 2 units of the same platform. Mind the notation
"[Board A or B]". The following steps assumes both platforms are connected
to each other via an Ethernet connection and user has a terminal open

**./run.sh <PLAT> <BOARD> <IFACE> [ACTION] [APP-COMPONENT] [MODE] <Options>**        

**Example:    
  ./run.sh i225 tgl enp169s0 run listener single -D 1**       

\<PLAT\>: Network Interface Card. Example: i225 etc   
\<BOARD\>: Example: icx, tglu   
\<IFACE\>: Netork interface. Example: enp169s0   
\[ACTION\]: setup or run   
\[APP-COMPONENT\]: listener, talker   
\[MODE\]: single, dual, mix   
- In single mode, only 1 talker and listener apps are running via AF_XDP socket.   
- In dual mode, 2 talker and 2 listener apps are running via AF_XDP socket.   
- In mix mode, 2 talker and 2 listener apps are running. Each talker and listener   
        running via AF_XDP and AF_PACKET respectively.   
\<Options\>: are specified below and vary for listener and talker applications   

Run Listener App - Listening to the incoming L2 packet:     
---------------------------------------------------   

[Board A]:      
Environment setup:   
**./run.sh i225 tgl enp169s0 setup listener**      

run:    
**./run.sh i225 tgl enp169s0 run listener single -f output.csv**    

Options:     
 -p|--portmask: hexadecimal bitmask of ports to configure. Default is 0x1  
 -q|--lcoreq: NQ: number of queue (=ports) per lcore (default is 1)  
 -f|--filename: LATENCY OUTPUT FILENAME: length should be less than 30 characters, preferably with .csv extension. Default is 'default_listenerOPfile.csv' if option not provided  
 -D|--debug: 1 to enable debug mode, 0 default disable debug mode   
 -h|--help, Print help   



Run Talker App - Sending L2 packet to the Listener App:     
---------------------------------------------------   
[Board B]:    

Environment setup:   
**./run.sh i225 tgl enp169s0 setup talker**

run:    
**./run.sh i225 tgl enp169s0 run talker single -T 500 -d 22:BB:22:BB:22:BB -c 5000 -D 0**  

Options:  
 -p|--portmask: hexadecimal bitmask of ports to configure. Default is 0x1   
 -q|--lcoreq: NQ: number of queue (=ports) per lcore (default is 1)   
 -D|--debug: 1 to enable debug mode, 0 default disable debug mode
 -T|--tperiod: Packet will be transmit each PERIOD microseconds (must >=300us, 3000us by default, 5000000 max)
 -d|--destmac: Destination MAC address: use ':' format, default is 22:bb:22:bb:22:bb
 -c|--pktcnt: Total packet to be send to destination (100000 by default, max 2000000)
 -h|--help, Print help    

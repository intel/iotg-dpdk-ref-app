DPDK TALKER/LISTENER App via AF_XDP PMD
========================================
This is an DPDK Application which has two components.
1. Talker: This transmits the packets
2. Listener: This Listens to the packets transmitted by talker.

This application needs to be executed on 2 boards.

Features of DPDK application:
============================
1. Latency Calculation: This provides the latency of the packet: This is the time from the packet being transmitted to received.
2. Provides and output file with latency graph
3. We can spawn two listeners and two talkers on different queues.
4. Console output provides details likes standard deviation, Jitter, Latency.Jitter output is displayed on console in master.


HARDWARE Requirement  
====================  
Two PC/VM/boards with Network Connectivity. Both machines' IP should be ping able to each other.   
OS: Linux Kernel with XDP support, tested on Ubuntu 20.04 kernel 5.4 and 5.10  

DPDK 21.11
==========
This version is compatible with DPDK 21.11.  
Please find in other branches for different DPDK compatible version.  
DPDK library installation guide: https://core.dpdk.org/doc/quick-start/

SETUP ENVIRONMENT
====================
sudoer yourself 
--------------- 
sudo -i

Huge Page
----------
mkdir -p /dev/hugepages  
mountpoint -q /dev/hugepages || mount -t hugetlbfs nodev /dev/hugepages  
echo 256 > /sys/devices/system/node/node0/hugepages/hugepages-2048kB/nr_hugepages  


PTP CLOCK SYNC IN BOTH TALKER AND LISTENER MACHINES 
====================================================  
Run following in TALKER machine and follow by LISTENER machine:  
sudo /ptp/time_sync.sh i225     

Validate following in listener machine 
--------------------------------------- 
tail /var/log/ptp4l.log  
test: 
ptp4l.log => rms value must below than 100us 

tail /var/log/phc2sys.log   
test: 
phc2sys => offset value must be below than 100us 

Note: not all NIC with PTP feature, please check your NIC specification, you could ignore this section if not eligible.

To verify if the NIC supports PTP feature:
sudo ethtool -T  enp0s8 
Check on following: 
PTP Hardware Clock: 0 

RUN LISTENER 
==========
An executable program listen to all L2 (MAC/Ethernet level) broadcasting data frame

compile:  
make

Route Packet to queue 3 
----------------------------------
If you're using PTP to sync clock between talker and listener mentioned in above section, please route the listener packet RX (receiving/ingress) to queue 3 as below:  

ethtool -K enp169s0 ntuple on 
ethtool -N enp169s0 flow-type ether vlan 24576 vlan-mask 0x1FFF action 3 

Validate result  
---------------  
ethtool --show-ntuple enp169s0   

Run on queue=3    
-----------------------------  
**sudo /data/yockgenm/dpdk-demo01/listener/build/listener -l 2-3 -n 1 --vdev=net_af_xdp0,iface=enp169s0,start_queue=3 -- -p 0x1 -D 1**    


Options  
-p PORTMASK: hexadecimal bitmask of ports to configure  
-q NQ: number of queue (=ports) per lcore (default is 1)  
-f LATENCY OUTPUT FILENAME: length should be less than 30 characters, preferably with .csv extension. Default is 'default_listenerOPfile.csv' if option not provided  
-D [1,0] (1 to enable debug mode, 0 default disable debug mode)  
--[no-]mac-updating: Enable or disable MAC addresses updating (enabled by default)  
      When enabled:  
       - The source MAC address is replaced by the TX port MAC address  
       - The destination MAC address is replaced by 02:00:00:00:00:TX_PORT_ID  
--portmap: Configure forwarding port pair mapping  


RUN Talker 
==========
An executable program receiving L2 (MAC/Ethernet level) data frame

compile:  
make

Run  
====
**sudo ./dpdk-demo01/talker/build/talker -l 1 -n 1 --vdev=net_af_xdp0,iface=enp169s0,start_queue=1  -- -p 0x1 -T 300 -d  00:A0:C9:00:00:02 -D 1 -c 150000**   

Options  
  -p PORTMASK: hexadecimal bitmask of ports to configure  
  -q NQ: number of queue (=ports) per lcore (default is 1)
  -T PERIOD: packet will be transmit each PERIOD microseconds (must >=300us, 3000us by default, 5000000 max)
  -d Destination MAC address: use ':' format, for example, 08:00:27:cf:69:3e  
  -D [1,0] (1 to enable debug mode, 0 default disable debug mode)
  -c Total packet to be send to destination (100000 by default, max 2000000)
  --[no-]mac-updating: Enable or disable MAC addresses updating (enabled by default)  
      When enabled:  
       - The source MAC address is replaced by the TX port MAC address  
       - The destination MAC address is replaced by 02:00:00:00:00:TX_PORT_ID  
  --portmap: Configure forwarding port pair mapping  

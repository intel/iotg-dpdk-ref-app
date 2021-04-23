HARDWARE/VM PLATFORM
=====================
VM:VirtualBox OS: UBUNTU 20.04  
NIC: 4 (1 Primary Bridge Mode, 3 INTERNAL - for dpdk prototype)  
Ethernet controller: Intel Corporation 82540EM Gigabit Ethernet Controller (rev 02)  - all 4 

INSTALL DPDK
====================
https://core.dpdk.org/doc/quick-start/

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


Bring Down NIC for DPDK prototype
---------------------------------
/home/yockgenm/dpdk# ifconfig enp0s8 down  
/home/yockgenm/dpdk# ifconfig enp0s9 down  

Enable unsafe iommu mode (need study why such)
---------------------------------------------
echo 1 > /sys/module/vfio/parameters/enable_unsafe_noiommu_mode  

Bind Down NICs to DPDK compatible driver
-------------------------------------------
/home/yockgenm/dpdk# python3 /home/yockgen/dpdk/usertools/dpdk-devbind.py -b vfio-pci 0000:00:08.0  
/home/yockgenm/dpdk# python3 /home/yockgen/dpdk/usertools/dpdk-devbind.py -b vfio-pci 0000:00:09.0  

To confirm:
/home/yockgenm/dpdk# python3 /home/yockgen/dpdk/usertools/dpdk-devbind.py -s  

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
make static  

run:  
sudo /home/yockgen/dpdk/examples/listener/build/listener -l 2-3 -n 1 -a 0000:00:08.0 -d librte_net_virtio.so -d librte_mempool_ring.so -- -p 0x1 -T 1

If you want to run using bifurcated level PMD like AF_PACKET, AF_XDP (mean still through Linux kernel and share NIC with other non-DPDK app), please do not bring down the interface (ifconfig xxx down) and ignore the dpdk-devbind.py steps, run following:  

sudo /home/yockgen/dpdk-demo01/listener/build/listener -l 2-3 -n 1 --vdev=net_af_xdp0,iface=enp0s8  -d librte_net_virtio.so -d librte_mempool_ring.so -- -p 0x1 -T 1  

Route Packet to queue 3 in listener
----------------------------------
If you're using PTP to sync clock between talker and listener mentioned in above section, please route the listener packet RX (receiving/ingress) to queue=1 as below:  

ethtool -K enp169s0 ntuple on 
ethtool -N enp169s0 flow-type ether vlan 24576 vlan-mask 0x1FFF action 3 

//validate result  
ethtool --show-ntuple enp169s0   

//running listner on rx queue=3    
sudo /home/yockgen/dpdk-demo01/listener/build/listener -l 2-3 -n 1 --vdev=net_af_xdp0,iface=enp0s8,start_queue=3 -- -p 0x1 -T 1 -D 1     

RUN Talker 
==========
An executable program sending L2 (MAC/Ethernet level) data frame

compile:  
make static  

run:  
sudo /home/yockgen/dpdk/examples/talker/build/talker -l 1 -n 1 -a 0000:00:09.0 -d librte_net_virtio.so -d librte_mempool_ring.so -- -p 0x1 -T 1 -d 08:00:27:cf:69:3e  -D 1

If you want to run using bifurcated level PMD like AF_PACKET, AF_XDP (mean still through Linux kernel and share NIC with other non-DPDK app), please do not bring down the interface (ifconfig xxx down) and ignore the dpdk-devbind.py steps, run following:  

sudo /home/yockgen/dpdk-demo01/l2fwd/build/talker -l 1 -n 1 --vdev=net_af_xdp1,iface=enp0s9 -- -p 0x1 -T 1 -d 08:00:27:cf:69:3e  


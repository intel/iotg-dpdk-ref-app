# dpdk-demo01


HARDWARE/VM PLATFORM
=====================
VM:VirtualBox OS: UBUNTU 20.04
NIC: 4 (1 Primary Bridge Mode, 3 INTERNAL - for dpdk prototype)

SETUP ENVIRONMENT
====================
sudoer yourself - as DPDK need root most of times 
---------------------------------------------------
sudo -i

Huge Page
---------------
mkdir -p /dev/hugepages
mountpoint -q /dev/hugepages || mount -t hugetlbfs nodev /dev/hugepages
echo 256 > /sys/devices/system/node/node0/hugepages/hugepages-2048kB/nr_hugepages


Bring Down NIC for DPDK prototype
---------------------------------
root@yockgenm-VirtualBox:/home/yockgenm/dpdk# ifconfig enp0s8 down
root@yockgenm-VirtualBox:/home/yockgenm/dpdk# ifconfig enp0s9 down

Enable unsafe iommu mode (need study why such)
---------------------------------------------
root@yockgenm-VirtualBox:/home/yockgenm/dpdk# echo 1 > /sys/module/vfio/parameters/enable_unsafe_noiommu_mode

Bind Down NICs to DPDK compatible driver
-------------------------------------------
root@yockgenm-VirtualBox:/home/yockgenm/dpdk# python3 /home/yockgen/dpdk/usertools/dpdk-devbind.py -b vfio-pci 0000:00:08.0
root@yockgenm-VirtualBox:/home/yockgenm/dpdk# python3 /home/yockgen/dpdk/usertools/dpdk-devbind.py -b vfio-pci 0000:00:09.0

To confirm:
root@yockgenm-VirtualBox:/home/yockgenm/dpdk# python3 /home/yockgen/dpdk/usertools/dpdk-devbind.py -s

RUN L2FWD (FIRST TERMINAL)
==========================
sudo /home/yockgen/dpdk/examples/l2fwd/build/l2fwd -l 2-3 -n 1 -a 0000:00:08.0 -d librte_net_virtio.so -d librte_mempool_ring.so -- -p 0x1 -T 1

RUN PKTGEN (2ND TERMINAL)
=========================
sudo -E ./Builddir/app/pktgen -l 0-1 -n 1 --file-prefix pg -a 0000:00:09.0 -d librte_net_e1000.so -d librte_mempool_ring.so -- -T - P -m 1.0 

PKTGEN CMD ONCE IN PKTGEN PROMPT
================================
set 0 dst mac 08:00:27:73:58:26 
set 0 count 1000
start 0
stop 0

*To get mac address, look at L2FWD terminal output, the mac showing top left on each refresh 
*Once start 0 triggered, L2FWD terminal should be seeing spike on receiving (else, the setup considered failed)




RUN L3FWD (FIRST TERMINAL) - WIP
==========================
working but not clear:
/home/yockgen/dpdk/examples/l3fwd/build/l3fwd -l 1 -n 4  --  -p 0x1 --config="(0,0,1)" --parse-ptype
source code:
root@yockgen-VirtualBox:/home/yockgen/dpdk/examples/l3fwd# nano +249 ./l3fwd_lpm.c

To test if NIC support multiple queue
=======================================
yockgen@yockgen-VirtualBox:~/Desktop$ ethtool -l enp0s3
Channel parameters for enp0s3:
Cannot get device channel parameters
: Operation not supported


wip:
=====
sudo /home/yockgen/dpdk/examples/l3fwd/build/l3fwd -l 2-3 -n 1  -d librte_net_virtio.so -d librte_mempool_ring.so --  -p 0x3 --mode=eventdev --eventq-sched=ordered 
/home/yockgen/dpdk/examples/l3fwd/build/l3fwd -l 1,2 -n 4 --  -p 0x3 --config="(0,0,1),(1,0,2)"
/home/yockgen/dpdk/examples/l3fwd/build/l3fwd -l 1,2 -n 1 --  -p 0x3 --config="(0,0,1),(1,0,2)"


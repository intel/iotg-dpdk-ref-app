# dpdk-demo01


*mkdir -p /dev/hugepages
*mountpoint -q /dev/hugepages || mount -t hugetlbfs nodev /dev/hugepages
echo 64 > /sys/devices/system/node/node0/hugepages/hugepages-2048kB/nr_hugepages

root@yockgenm-VirtualBox:/home/yockgenm/dpdk# echo 1 > /sys/module/vfio/parameters/enable_unsafe_noiommu_mode
root@yockgenm-VirtualBox:/home/yockgenm/dpdk# python3 ./usertools/dpdk-devbind.py -b vfio-pci 0000:00:08.0
yockgen=/sys/bus/pci/drivers/vfio-pci/bind devid=0000:00:08.0
root@yockgenm-VirtualBox:/home/yockgenm/dpdk# python3 ./usertools/dpdk-devbind.py -b vfio-pci 0000:00:09.0
yockgen=/sys/bus/pci/drivers/vfio-pci/bind devid=0000:00:09.0


root@yockgenm-VirtualBox:/home/yockgenm/dpdk/dpdk-demo/dpdk-demo01# make
ln -sf basicfwd-shared build/basicfwd
root@yockgenm-VirtualBox:/home/yockgenm/dpdk/dpdk-demo/dpdk-demo01# ./build/basicfwd

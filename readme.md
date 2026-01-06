## Make rk3588 image based on an existing OS

**Do it on rk3588**
1. copy files from the existing OS by following code:

tar --xattrs --acls --numeric-owner --one-file-system     --exclude=/proc --exclude=/sys --exclude=/dev  --exclude=/run --exclude=/tmp  --exclude=/media  --exclude=/mnt     --exclude=/lost+found   --exclude=/var/cache/apt/archives/* --exclude=/var/lib/docker/*   --exclude=/var/tmp/*     -czpf rootfs.tar.gz     ./


**Do it on your local computer**
2. copy the empressed files to local computer by:

sudo rsync -avx lumosbot@192.168.54.110:/rootfs.tar.gz ./

3. unzip the roots.tar.gz

tar -zxvf rootfs.tar.gz -C ./rootfs

4. making image folder

dd if=/dev/zero of=rk3588_20260106.img bs=1G count=12

sudo mkfs.ext4 -F -L linuxroot rk3588_20240103.img

mkdir ubuntu-mount

sudo mount rk3588_20260106.img ubuntu-mount

sudo cp -rfp rootfs/* ubuntu-mount  

sudo umount ubuntu-mount

sudo e2fsck -p -f rk3588_20260106.img
sudo resize2fs -M rk3588_20260106.img
sudo mv rk3588_20260106.img ./output/Image/rootfs.img

sudo ./pack.sh

echo "try to upgrade, please connect rk3588 board ... "
sleep 2

sudo upgrade_tool uf new_update.img






## How to use unpack.sh and pack.sh


1. 解包
    把官方发布的固件拷贝到当前目录，重命名为update.img , 执行unpack.sh
    解包完成后，生成的文件在output目录下.

2. 合包
    保持当前目录结构，文件名等不变，用客户自己的文件替换output/下同名的文件
    执行pack.sh, 执行完后，生成new_update.img，即为打包好的固件
	rootfs文件名必须为rootfs.img
	parameter.txt文件名必须为parameter.txt

注意：
	合包过程中，如果rootfs分区不是最后一个分区，那么程序会根据rootfs文件的大小，
	自动修改parameter.txt中rootfs分区的大小。
	如果用户自己有改动parameter.txt，请留意整个合包的流程。



#!/bin/bash
# Variables for file names and paths
ROOTFS_TAR="rootfs.tar.gz"
IMG_FILE="rk3588_20260106.img"
OUTPUT_DIR="./output/Image"
MOUNT_DIR="./ubuntu-mount"

# 1) Get rootfs.tar
echo "0. tar ubuntu sys on a rk3588 by following commands: "
# tar --xattrs --acls --numeric-owner --one-file-system  --exclude=/proc --exclude=/sys --exclude=/dev  --exclude=/run --exclude=/tmp  --exclude=/media  --exclude=/mnt     --exclude=/lost+found   --exclude=/var/cache/apt/archives/* --exclude=/var/lib/docker/*   --exclude=/var/tmp/*   -czpf rootfs.tar.gz     ./

echo "1. Downloading rootfs ..."
# Uncomment and modify this line for actual rsync or download command
# sudo rsync -avx lumosbot@192.168.54.110:/rootfs.tar.gz ./

# 2) Unzip the rootfs.tar.gz
echo "2. Extracting rootfs ..."
if [ -d "./rootfs" ]; then
    echo "./rootfs exists, deleting ..."
    sudo rm -rf ./rootfs
fi
mkdir rootfs
if [ ! -f "$ROOTFS_TAR" ]; then
    echo "Error: $ROOTFS_TAR does not exist. Exiting..."
    exit 1
fi
tar -zxvf $ROOTFS_TAR -C ./rootfs

# 3) Create image file
echo "3. Creating image file ..."
dd if=/dev/zero of=$IMG_FILE bs=1G count=12 status=progress

# 4) Create filesystem on the image
echo "4. Formatting the image with ext4 filesystem ..."
sudo mkfs.ext4 -F -L linuxroot $IMG_FILE

# 5) Mount the image
echo "5. Mounting the image ..."
rm -rf $MOUNT_DIR
mkdir $MOUNT_DIR
sudo mount $IMG_FILE $MOUNT_DIR

# 6) Copy rootfs to the mounted image
echo "6. Copying rootfs to the mounted image ..."
sudo cp -rfp rootfs/* $MOUNT_DIR

# 7) Unmount the image
echo "7. Unmounting the image ..."
sudo umount $MOUNT_DIR

# 8) Check and resize the image filesystem
echo "8. Checking and resizing the filesystem ..."
sudo e2fsck -p -f $IMG_FILE
sudo resize2fs -M $IMG_FILE

# 9) Move the image to output directory
echo "9. Moving image to output directory ..."

echo "You should have a origial image call update.img, you should copy it here ..."
sudo cp ./../update.img ./
sudo ./unpack.sh

sudo mv $IMG_FILE $OUTPUT_DIR/rootfs.img

# 10) Execute the pack.sh script
echo "10. Running pack.sh ..."
sudo ./pack.sh

# 11) Perform the upgrade with the new image
echo "11. Performing upgrade with new image ..."
DEVICE_OUTPUT=$(sudo upgrade_tool ld)
if [ -n "$DEVICE_OUTPUT" ]; then
    echo "Device found, proceeding with upgrade ..."
    sudo upgrade_tool uf new_update.img
else
    echo "No device found. Exiting..."
    exit 1
fi

# Clean up
echo "12. Cleaning up ..."
sudo rm -rf $MOUNT_DIR rootfs

echo "Process complete!"


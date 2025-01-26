#!/bin/bash

set -uo pipefail
trap 's=$?; echo "$0: Error on line "$LINENO": $BASH_COMMAND"; exit $s' ERR

# REPO_URL="https://s3.eu-west-2.amazonaws.com/mdaffin-arch/repo/x86_64"

##### Get infomation from user
hostname=$(dialog --stdout --inputbox "Enter hostname" 0 0) || exit 1
clear
: ${hostname:?"hostname cannot be empty"}

user=$(dialog --stdout --inputbox "Enter admin username" 0 0) || exit 1
clear
: ${user:?"user cannot be empty"}

password=$(dialog --stdout --passwordbox "Enter admin password" 0 0) || exit 1
clear
: ${password:?"password cannot be empty"}
password2=$(dialog --stdout --passwordbox "Enter admin password again" 0 0) || exit 1
clear
[[ "$password" == "$password2" ]] || ( echo "Passwords did not match"; exit 1; )

devicelist=$(lsblk -dplnx size -o name,size | grep -Ev "boot|rpmb|loop" | tac)
device=$(dialog --stdout --menu "Select installation disk" 0 0 0 ${devicelist}) || exit 1
clear

##### Set up logging
exec 1> >(tee "stdout.log")
exec 2> >(tee "stderr.log")

##### Enable Network Time Protocol (NTP) to synchronize clock
timedatectl set-ntp true

##### Setup params for configurating swap partition
# swap_size=$(free --mebi | awk '/Mem:/ {print $2}')
# swap_end=$(( $swap_size + 129 + 1 ))MiB

##### Create partitions
parted --script "${device}" -- mklabel gpt \
  mkpart ESP fat32 1Mib 321MiB \
  set 1 boot on \
  mkpart primary ext4 321MiB 50GiB \
  mkpart primary ext4 50GiB 100%

# Simple globbing was not enough as on one device I needed to match /dev/mmcblk0p1
# but not /dev/mmcblk0boot1 while being able to match /dev/sda1 on other devices.
part_boot="$(ls ${device}* | grep -E "^${device}p?1$")"
# part_swap="$(ls ${device}* | grep -E "^${device}p?2$")"
part_root="$(ls ${device}* | grep -E "^${device}p?2$")"
part_home="$(ls ${device}* | grep -E "^${device}p?3$")"

##### Remove file systems and labels from given partitions
wipefs "${part_boot}"
wipefs "${part_root}"
wipefs "${part_home}"

# Create new artitions
mkfs.vfat -F32 "${part_boot}"
# mkswap "${part_swap}"
mkfs.ext4 "${part_root}"
mkfs.ext4 "${part_home}"

# swapon "${part_swap}"
# mount "${part_root}" /mnt
# mkdir /mnt/boot
# mount "${part_boot}" /mnt/boot

mount "${part_root}" /mnt
mkdir -p /mnt/boot
mount "${part_boot}" /mnt/boot
mkdir /mnt/home
mount "${part_home}" /mnt/home


pacstrap /mnt base linux linux-firmware
# pacstrap /mnt mdaffin-desktop

# ????
genfstab -U /mnt >> /mnt/etc/fstab
echo "${hostname}" > /mnt/etc/hostname

arch-chroot /mnt bootctl install

cat <<EOF > /mnt/boot/loader/loader.conf
default arch
EOF

cat <<EOF > /mnt/boot/loader/entries/arch.conf
title    Arch Linux
linux    /vmlinuz-linux
initrd   /initramfs-linux.img
options  root=PARTUUID=$(blkid -s PARTUUID -o value "$part_root") rw
EOF

ln -sf /usr/share/zoneinfo/Europe/Warsaw /etc/localtime
hwclock --systohc
# locale-gen

echo "LANG=pl_PL.UTF-8" > /mnt/etc/locale.conf
arch-chroot /mnt locale-gen

arch-chroot /mnt useradd -mU -s /usr/bin/fish -G wheel,uucp,video,audio,storage,games,input "$user"
arch-chroot /mnt chsh -s /usr/bin/fish

echo "$user:$password" | chpasswd --root /mnt
echo "root:$password" | chpasswd --root /mnt

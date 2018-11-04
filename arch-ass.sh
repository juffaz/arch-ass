#!/bin/bash
# WARNING: this script will destroy data on the selected disk.
# This script can be run by executing the following:
#   curl -sL https://git.io/fxp87 | bash
set -uo pipefail
trap 's=$?; echo "$0: Error on line "$LINENO": $BASH_COMMAND"; exit $s' ERR

#REPO_URL="Server = http://archlinux.mirror.wearetriple.com/$repo/os/$arch"

### Get infomation from user ###
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

### Set up logging ###
exec 1> >(tee "stdout.log")
exec 2> >(tee "stderr.log")

timedatectl set-ntp true

### Setup the disk and partitions ###
swap_size=$(free --mebi | awk '/Mem:/ {print $2}')
swap_end=$(( $swap_size + 129 + 1 ))MiB

parted --script "${device}" -- mklabel gpt \
  mkpart ESP fat32 1Mib 600MiB \
  set 1 boot on \
  mkpart primary linux-swap 600MiB ${swap_end} \
  mkpart primary ext4 ${swap_end} 100%

# Simple globbing was not enough as on one device I needed to match /dev/mmcblk0p1
# but not /dev/mmcblk0boot1 while being able to match /dev/sda1 on other devices.
part_boot="$(ls ${device}* | grep -E "^${device}p?1$")"
part_swap="$(ls ${device}* | grep -E "^${device}p?2$")"
part_root="$(ls ${device}* | grep -E "^${device}p?3$")"

wipefs "${part_boot}"
wipefs "${part_swap}"
wipefs "${part_root}"

mkfs.vfat -F32 "${part_boot}"
mkswap "${part_swap}"
mkfs.f2fs -f "${part_root}"

swapon "${part_swap}"
mount "${part_root}" /mnt
mkdir /mnt/boot
mount "${part_boot}" /mnt/boot

### Install and configure the basic system ###
#cat >>/etc/pacman.conf <<EOF
#[multilib]
#Include = /etc/pacman.d/mirrorlist


#[archlinuxfr]
#SigLevel = Never
#Server = http://repo.archlinux.fr/$arch

#[blackarch]
#Server = https://www.mirrorservice.org/sites/blackarch.org/blackarch//$repo/os/$arch
#EOF

#[Netherlands]
#SigLevel = Optional TrustAll
#Server = $REPO_URL

## pacstrap /mnt base
pacstrap /mnt base base-devel networkmanager zsh vim git efibootmgr dialog wpa_supplicant sudo archlinux-keyring nmap curl tcpdump xterm xorg xorg-xinit mesa mate mate-extra network-manager-applet networkmanager
genfstab -t PARTUUID /mnt >> /mnt/etc/fstab
echo "${hostname}" > /mnt/etc/hostname

cat <<EOF >>/mnt/etc/pacman.conf 
[multilib]
Include = /etc/pacman.d/mirrorlist

[archlinuxfr]
SigLevel = Never
Server = http://repo.archlinux.fr/\$arch

[blackarch]
SigLevel = Optional TrustAll
Server = https://www.mirrorservice.org/sites/blackarch.org/blackarch//\$repo/os/\$arch

EOF


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


echo "LANG=en_GB.UTF-8" > /mnt/etc/locale.conf

arch-chroot /mnt useradd -mU -s /usr/bin/zsh -G wheel,uucp,video,audio,storage,games,input "$user"
arch-chroot /mnt chsh -s /usr/bin/zsh
echo "$user:$password" | chroot /mnt chpasswd 
echo "root:$password" | chroot /mnt chpasswd
echo "$user ALL=(ALL) ALL" > /mnt/etc/sudoers.d/$user

#arch-chroot /mnt yes | arch-chroot /mnt pacman -Syy --noconfirm 
#arch-chroot /mnt pacman -Syy nmap curl tcpdump xterm xorg xorg-xinit mesa mate mate-extra network-manager-applet networkmanager yay   --noconfirm
echo "exec mate-session" > /mnt/home/juff/.xinitrc 
chroot /mnt systemctl enable NetworkManager
umount /mnt/boot
umount /mnt
reboot () { echo 'Install success complete. Reboot? (y/n)' && read x && [[ "$x" == "y" ]] && /sbin/reboot; }

#!/bin/bash

# Exit on errors
set -e

# Welcome message
echo "Welcome to the customized Arch Linux installation script!"
echo "This script will guide you through a highly customizable Arch Linux installation."
echo ""

# Prompt user for timezone
read -p "Enter your timezone (e.g., Europe/Berlin): " timezone

# Prompt user for locale
echo ""
read -p "Enter the locales you want to enable (space-separated, e.g., en_US.UTF-8 de_DE.UTF-8): " locales

# Prompt user for key layout
read -p "Enter your keyboard layout (e.g., us, de, fr): " keylayout
loadkeys "$keylayout"

# Prompt user for root password and user account
read -s -p "Enter the root password: " root_password
echo ""
read -p "Enter the username for the new user account: " username
read -s -p "Enter the password for the $username account: " user_password
echo ""

# Disk setup
lsblk
echo ""
echo "Available disks:"
fdisk -l
echo ""
read -p "Enter the disk to partition (e.g., /dev/sda): " disk
cfdisk "$disk"

# Prompt user for partitions
read -p "Enter the partition number for EFI system partition (e.g., 1): " efi_part
read -p "Enter the partition number for BTRFS partition (e.g., 2): " btrfs_part
read -p "Did you create a swap partition? (yes/no): " created_swap
if [[ "$created_swap" == "yes" ]]; then
    read -p "Enter the partition number for swap (e.g., 3): " swap_part
fi

# Construct partition paths
efi_part="${disk}${efi_part}"
btrfs_part="${disk}${btrfs_part}"
if [[ "$created_swap" == "yes" ]]; then
    swap_part="${disk}${swap_part}"
fi

# Format partitions and set labels
echo "Formatting partitions..."
mkfs.fat -F32 -n "EFI" "$efi_part"
mkfs.btrfs -L "ROOT" "$btrfs_part"
if [[ "$created_swap" == "yes" ]]; then
    mkswap -L "SWAP" "$swap_part"
    swapon "$swap_part"
fi

# Mount BTRFS and create essential subvolumes
echo "Mounting BTRFS partition and creating essential subvolumes..."
mount "$btrfs_part" /mnt
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@snapshots
umount /mnt

# Remount subvolumes
mount -o subvol=@ "$btrfs_part" /mnt
mkdir -p /mnt/{boot,home,.snapshots}
mount -o subvol=@home "$btrfs_part" /mnt/home
mount -o subvol=@snapshots "$btrfs_part" /mnt/.snapshots
mount "$efi_part" /mnt/boot

# Optionally mount a Windows partition
read -p "Do you want to mount a Windows partition for dual-boot setup? (yes/no): " mount_windows
if [[ "$mount_windows" == "yes" ]]; then
    lsblk
    read -p "Enter the partition to mount (e.g., /dev/sda3): " windows_part
    mkdir -p /mnt/windows
    mount "$windows_part" /mnt/windows
fi

# Base package installation
base_packages="base linux-zen linux-zen-headers linux-firmware btrfs-progs grub efibootmgr os-prober networkmanager nano git neofetch zsh zsh-completions zsh-autosuggestions openssh man sudo snapper"
echo "Base packages: $base_packages"
read -p "Enter any additional packages to install (space-separated): " extra_packages
pacstrap /mnt $base_packages $extra_packages

# Generate fstab
genfstab -U /mnt >> /mnt/etc/fstab

# Chroot into the new system
arch-chroot /mnt /bin/bash <<EOF

# Set timezone
ln -sf /usr/share/zoneinfo/$timezone /etc/localtime
hwclock --systohc

# Configure locales
echo "$locales" > /etc/locale.gen
locale-gen
echo "LANG=$(echo $locales | cut -d' ' -f1)" > /etc/locale.conf

# Set hostname
echo "$hostname" > /etc/hostname
echo "127.0.0.1   localhost" >> /etc/hosts
echo "::1         localhost" >> /etc/hosts
echo "127.0.1.1   $hostname.localdomain $hostname" >> /etc/hosts

# Set root password
echo "root:$root_password" | chpasswd

# Create user and set password
useradd -m -G wheel -s /usr/bin/zsh "$username"
echo "$username:$user_password" | chpasswd

# Enable sudo for the wheel group
sed -i 's/^# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/' /etc/sudoers

# Enable services
systemctl enable NetworkManager sshd

# Configure GRUB
sed -i 's/^#GRUB_DISABLE_OS_PROBER=false/GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

# Install and set up Snapper
snapper --config root create-config /
snapper --config home create-config /home
pacman -Syu snap-pac grub-btrfs --noconfirm

# Install Yay (AUR Helper)
git clone https://aur.archlinux.org/yay.git /home/$username/yay
chown -R $username:$username /home/$username/yay
cd /home/$username/yay
sudo -u $username makepkg -si --noconfirm
EOF

# Final message
echo "Installation complete! Reboot into your new Arch Linux system."

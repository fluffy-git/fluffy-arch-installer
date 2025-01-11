#!/bin/bash

# Exit on errors
set -e

# Color formatting
BOLD=$(tput bold)
NORMAL=$(tput sgr0)
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
BLUE=$(tput setaf 4)
CYAN=$(tput setaf 6)
RESET=$(tput sgr0)

# Function for input validation
validate_input() {
    local input="$1"
    if [[ -z "$input" ]]; then
        echo "${RED}Error: Input cannot be empty.${RESET}"
        return 1
    fi
    return 0
}

# Function for validated prompt
prompt_input() {
    local prompt_message="$1"
    local input
    while true; do
        read -p "${BOLD}${prompt_message}${RESET} " input
        if validate_input "$input"; then
            echo "$input"
            break
        fi
    done
}

clear

# Welcome message
echo "${CYAN}Welcome to the customized Arch Linux installation script!${RESET}"
echo "${BOLD}This script will guide you through a highly customizable Arch Linux installation.${RESET}"
echo ""

# Prompt user for timezone
clear
timezone=$(prompt_input "Enter your timezone (e.g., Europe/Berlin):")

# Prompt user for locale
clear
echo "${BOLD}Enter the locales you want to enable.${RESET}"
echo "${GREEN}Example: en_US de_DE${RESET}"
echo "The script will automatically append UTF-8."
locale_input=$(prompt_input "Enter locales (space-separated):")
IFS=' ' read -r -a locale_array <<< "$locale_input"

# Prompt user for keyboard layout
clear
keylayout=$(prompt_input "Enter your keyboard layout (e.g., us, de, fr):")
loadkeys "$keylayout"

# Prompt user for root password and user account
clear
root_password=$(prompt_input "Enter the root password (input hidden):" -s)
username=$(prompt_input "Enter the username for the new user account:")
user_password=$(prompt_input "Enter the password for $username (input hidden):" -s)

# Disk setup
clear
lsblk
echo "${BOLD}Available disks:${RESET}"
fdisk -l
disk=$(prompt_input "Enter the disk to partition (e.g., /dev/sda):")
cfdisk "$disk"

# Prompt user for partitions
efi_part=$(prompt_input "Enter the partition number for EFI system partition (e.g., 1):")
btrfs_part=$(prompt_input "Enter the partition number for BTRFS partition (e.g., 2):")
echo "Did you create a swap partition? (yes/no):"
read created_swap
if [[ "$created_swap" == "yes" ]]; then
    swap_part=$(prompt_input "Enter the partition number for swap (e.g., 3):")
fi

# Construct partition paths
efi_part="${disk}${efi_part}"
btrfs_part="${disk}${btrfs_part}"
if [[ "$created_swap" == "yes" ]]; then
    swap_part="${disk}${swap_part}"
fi

# Format partitions and set labels
clear
echo "${YELLOW}Formatting partitions...${RESET}"
mkfs.fat -F32 -n "EFI" "$efi_part"
mkfs.btrfs -L "ROOT" "$btrfs_part"
if [[ "$created_swap" == "yes" ]]; then
    mkswap -L "SWAP" "$swap_part"
    swapon "$swap_part"
fi

# Mount BTRFS and create essential subvolumes
echo "${YELLOW}Mounting BTRFS partition and creating essential subvolumes...${RESET}"
mount "$btrfs_part" /mnt
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
umount /mnt

# Remount subvolumes
mount -o subvol=@ "$btrfs_part" /mnt
mkdir -p /mnt/{boot,home}
mount -o subvol=@home "$btrfs_part" /mnt/home
mount "$efi_part" /mnt/boot

# Base package installation
clear
base_packages="base linux-zen linux-zen-headers linux-firmware btrfs-progs grub efibootmgr os-prober networkmanager nano git neofetch zsh zsh-completions zsh-autosuggestions openssh man sudo snapper"
echo "${BOLD}Base packages:${RESET} $base_packages"
read -p "${BOLD}Enter any additional packages to install (space-separated):${RESET} " extra_packages
pacstrap /mnt $base_packages $extra_packages

# Generate fstab
genfstab -U /mnt >> /mnt/etc/fstab

# Copy network settings
if [ -d /etc/NetworkManager/system-connections ]; then
    echo "${YELLOW}Copying network settings...${RESET}"
    cp -r /etc/NetworkManager/system-connections /mnt/etc/NetworkManager/ || {
        echo "${RED}Warning: Failed to copy network settings. Continuing without them.${RESET}"
    }
else
    echo "${YELLOW}No network settings found to copy. Skipping this step.${RESET}"
fi

# Enter chroot and configure the system
arch-chroot /mnt /bin/bash <<EOF

# Set timezone
ln -sf /usr/share/zoneinfo/$timezone /etc/localtime
hwclock --systohc

# Configure locales
for locale in ${locale_array[@]}; do
    echo "${locale}.UTF-8 UTF-8" >> /etc/locale.gen
done
locale-gen
echo "LANG=${locale_array[0]}.UTF-8" > /etc/locale.conf

# Set hostname
hostname=$(prompt_input "Enter the hostname for this system:")
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

# Install yay and additional tools
pacman -S --noconfirm yay snap-pac grub-btrfs
EOF

# Final message
echo "${GREEN}Installation complete! Reboot into your new Arch Linux system.${RESET}"

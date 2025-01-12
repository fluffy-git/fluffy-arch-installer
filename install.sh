#!/bin/bash

# Exit on errors
set -e

# Colors and formatting
bold=$(tput bold)
normal=$(tput sgr0)
green=$(tput setaf 2)
yellow=$(tput setaf 3)
red=$(tput setaf 1)

# Functions for validation
validate_input() {
    local input="$1"
    while [[ -z "$input" ]]; do
        echo "${red}Input cannot be empty. Please try again.${normal}"
        read -p "$2" input
    done
    echo "$input"
}

# Welcome message
clear
echo "${bold}${green}Welcome to the customized Arch Linux installation script!${normal}"
echo "This script will guide you through a highly customizable Arch Linux installation."
echo ""

# Ensure the system is booted in UEFI mode
if [[ ! -d /sys/firmware/efi/efivars ]]; then
    echo "${red}Error: System is not booted in UEFI mode. Please reboot the system in UEFI mode.${normal}"
    exit 1
fi

# Prompt user for hostname
read -p "${bold}Enter the hostname for your system (e.g., archlinux): ${normal}" hostname
hostname=$(validate_input "$hostname" "Enter the hostname for your system (e.g., archlinux): ")

# Prompt user for timezone
read -p "${bold}Enter your timezone (e.g., Europe/Berlin): ${normal}" timezone
timezone=$(validate_input "$timezone" "Enter your timezone: ")

# Prompt user for locales
clear
#echo "${bold}Available locales:${normal}"
#grep -v '^#' /etc/locale.gen | less
#echo ""
read -p "${bold}Enter the locales to enable (space-separated, e.g., en_US de_DE): ${normal}" locales
locales=$(validate_input "$locales" "Enter the locales to enable: ")

# Prompt user for keyboard layout
clear
read -p "${bold}Enter your keyboard layout (e.g., us, de, fr): ${normal}" keylayout
keylayout=$(validate_input "$keylayout" "Enter your keyboard layout: ")
loadkeys "$keylayout"

# Prompt user for root password and user account
clear
read -s -p "${bold}Enter the root password: ${normal}" root_password
echo ""
read -p "${bold}Enter the username for the new user account: ${normal}" username
username=$(validate_input "$username" "Enter the username for the new user account: ")
read -s -p "${bold}Enter the password for the $username account: ${normal}" user_password
echo ""

# Disk setup
clear
lsblk -e 7,11
echo ""
read -p "${bold}Enter the disk to partition (e.g., sda): ${normal}" disk
disk=$(validate_input "$disk" "Enter the disk to partition: ")
disk="/dev/$disk"
cfdisk "$disk"

# Prompt user for partitions
clear
read -p "${bold}Enter the partition number for EFI system partition (e.g., 1): ${normal}" efi_part
efi_part=$(validate_input "$efi_part" "Enter the partition number for EFI system partition: ")
read -p "${bold}Enter the partition number for BTRFS partition (e.g., 2): ${normal}" btrfs_part
btrfs_part=$(validate_input "$btrfs_part" "Enter the partition number for BTRFS partition: ")
read -p "${bold}Did you create a swap partition? (yes/no): ${normal}" created_swap
if [[ "$created_swap" == "yes" ]]; then
    read -p "${bold}Enter the partition number for swap (e.g., 3): ${normal}" swap_part
    swap_part=$(validate_input "$swap_part" "Enter the partition number for swap: ")
fi

# Construct partition paths
efi_part="${disk}${efi_part}"
btrfs_part="${disk}${btrfs_part}"
if [[ "$created_swap" == "yes" ]]; then
    swap_part="${disk}${swap_part}"
fi

# Format partitions and set labels
clear
echo "${bold}${yellow}Wiping existing filesystem signatures...${normal}"
wipefs -a "$efi_part"
wipefs -a "$btrfs_part"
if [[ "$created_swap" == "yes" ]]; then
    wipefs -a "$swap_part"
fi

echo "${bold}${yellow}Formatting partitions...${normal}"
mkfs.fat -F32 -n "EFI" "$efi_part"
mkfs.btrfs -f -L "ROOT" "$btrfs_part"
if [[ "$created_swap" == "yes" ]]; then
    mkswap -f -L "SWAP" "$swap_part"
    swapon "$swap_part"
fi



# Mount BTRFS and create essential subvolumes
clear
echo "${bold}${yellow}Mounting BTRFS partition and creating subvolumes...${normal}"
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
echo "${bold}Base packages: ${base_packages}${normal}"
read -p "${bold}Enter any additional packages to install (space-separated): ${normal}" extra_packages
pacstrap /mnt $base_packages $extra_packages

# Generate fstab
clear
genfstab -U /mnt >> /mnt/etc/fstab

# Copy network settings
if [[ -d /etc/NetworkManager/system-connections ]]; then
    cp -r /etc/NetworkManager/system-connections /mnt/etc/NetworkManager/
else
    echo "${red}Network settings not found. Skipping network configuration copy.${normal}"
fi

# Chroot and configuration
arch-chroot /mnt /bin/bash <<EOF
ln -sf /usr/share/zoneinfo/$timezone /etc/localtime
hwclock --systohc
for locale in $locales; do
    echo "\${locale} UTF-8" >> /etc/locale.gen
done
locale-gen
echo "LANG=$(echo $locales | cut -d' ' -f1).UTF-8" > /etc/locale.conf
echo "$hostname" > /etc/hostname
echo "127.0.0.1   localhost" >> /etc/hosts
echo "::1         localhost" >> /etc/hosts
echo "127.0.1.1   $hostname.localdomain $hostname" >> /etc/hosts
echo "root:$root_password" | chpasswd
useradd -m -G wheel -s /usr/bin/zsh "$username"
echo "$username:$user_password" | chpasswd
sed -i 's/^# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/' /etc/sudoers
systemctl enable NetworkManager sshd

grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
echo "GRUB_DISABLE_OS_PROBER=false" >> /etc/default/grub
grub-mkconfig -o /boot/grub/grub.cfg

echo "KEYMAP=$keylayout" >> /etc/vconsole.conf
EOF

#Setup System Language
read -p "${bold}What locale do you want the system to use for Formats?: ${normal}" sys_locale
sys_locale=$(validate_input "$sys_locale" "What locale do you want the system to use for Formats?: ")
sys_locale_lang=$sys_locale
read -p "${bold}Do you want to use a diffrent Language to the Format Language: ${normal}" diff_lang_locale
if [[ "$diff_lang_locale" == "yes" ]]; then
    read -p "${bold}Which Locale do you want to use for the Language?: ${normal}" sys_locale_lang
    sys_locale_lang=$(validate_input "$sys_locale" "What locale do you want the system to use?: ")
fi
arch-chroot /mnt /bin/bash <<EOF
echo "LANG=$sys_locale.UTF-8" >> /etc/locale.conf
echo "LC_MESSAGES=$sys_locale_lang.UTF-8" >> /etc/locale.conf
EOF

# Yay installation
arch-chroot /mnt /bin/bash <<EOF
# Install required dependencies for building AUR packages
pacman -S --needed base-devel git fakeroot --noconfirm

# Switch to the new user and build yay
su - $username <<EOC
git clone https://aur.archlinux.org/yay.git /tmp/yay
cd /tmp/yay
makepkg -si --noconfirm
EOC
EOF




read -p "Do you want to enable a firewall (ufw)? (yes/no): " enable_firewall
if [[ "$enable_firewall" == "yes" ]]; then
    arch-chroot /mnt /bin/bash -c "pacman -Syu ufw --noconfirm && systemctl enable ufw && systemctl start ufw"
fi
arch-chroot /mnt /bin/bash <<EOF
if lspci | grep -i nvidia; then
    echo "NVIDIA GPU detected. Installing drivers..."
    pacman -Syu nvidia nvidia-settings nvidia-utils --noconfirm
elif lspci | grep -i amd; then
    echo "AMD GPU detected. Installing drivers..."
    pacman -Syu xf86-video-amdgpu --noconfirm
fi
EOF

# Install Zsh if it's not already installed
arch-chroot /mnt /bin/bash -c "pacman -Syu zsh --noconfirm"
# Set Zsh as the default shell system-wide
arch-chroot /mnt /bin/bash -c "chsh -s /bin/zsh root"
for user in $(ls /mnt/home); do
    arch-chroot /mnt /bin/bash -c "chsh -s /bin/zsh $user"
done

# Configure .zshrc for all users based on the provided configuration
arch-chroot /mnt /bin/bash <<EOF
echo "# Lines configured by zsh-newuser-install" > /etc/skel/.zshrc
echo "HISTFILE=~/.histfile" >> /etc/skel/.zshrc
echo "HISTSIZE=1000" >> /etc/skel/.zshrc
echo "SAVEHIST=1000" >> /etc/skel/.zshrc
echo "setopt autocd" >> /etc/skel/.zshrc
echo "bindkey -e" >> /etc/skel/.zshrc
echo "# End of lines configured by zsh-newuser-install" >> /etc/skel/.zshrc
echo "# The following lines were added by compinstall" >> /etc/skel/.zshrc
echo "zstyle :compinstall filename '/home/$username/.zshrc'" >> /etc/skel/.zshrc
echo "autoload -Uz compinit" >> /etc/skel/.zshrc
echo "compinit" >> /etc/skel/.zshrc
echo "# End of lines added by compinstall" >> /etc/skel/.zshrc
EOF
# Ensure new users have the default .zshrc (using /etc/skel)
arch-chroot /mnt /bin/bash -c "chmod 755 /etc/skel/.zshrc"
# Optionally install Oh My Zsh for all users
read -p "Do you want to install Oh My Zsh for all users? (yes/no): " install_omz
if [[ "$install_omz" == "yes" ]]; then
    arch-chroot /mnt /bin/bash -c "sh -c \"\$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)\" --unattended"
fi




# Final message
echo "${bold}${green}Installation complete! Reboot into your new Arch Linux system.${normal}"

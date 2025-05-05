#!/bin/bash

Exit on errors

set -e

Colors and formatting

bold=$(tput bold) normal=$(tput sgr0) green=$(tput setaf 2) yellow=$(tput setaf 3) red=$(tput setaf 1)

Functions for validation

validate_input() { local input="$1" while [[ -z "$input" ]]; do echo "${red}Input cannot be empty. Please try again.${normal}" read -p "$2" input done echo "$input" }

Welcome message

clear echo "${bold}${green}Welcome to the customized Arch Linux installation script!${normal}" echo "This script will guide you through a highly customizable Arch Linux installation." echo ""

Ensure the system is booted in UEFI mode

if [[ ! -d /sys/firmware/efi/efivars ]]; then echo "${red}Error: System is not booted in UEFI mode. Please reboot the system in UEFI mode.${normal}" exit 1 fi

Prompt user for hostname

read -p "${bold}Enter the hostname for your system (e.g., archlinux): ${normal}" hostname hostname=$(validate_input "$hostname" "Enter the hostname for your system (e.g., archlinux): ")

Prompt user for timezone

read -p "${bold}Enter your timezone (e.g., Europe/Berlin): ${normal}" timezone timezone=$(validate_input "$timezone" "Enter your timezone: ")

Prompt user for locales

read -p "${bold}Enter the locales to enable (space-separated, e.g., en_US de_DE): ${normal}" locales locales=$(validate_input "$locales" "Enter your locales to enable: ") locales=$(echo "$locales" | sed 's/\b[^ ]*\b/\1.UTF-8/g')

Prompt user for language and format locale

read -p "${bold}Enter your language locale (e.g., en_US): ${normal}" language_locale language_locale=$(validate_input "$language_locale" "Enter your language locale (e.g., en_US): ") language_locale="${language_locale}.UTF-8" read -p "${bold}Enter your format locale (e.g., de_DE) or press Enter to use the language locale: ${normal}" format_locale if [[ -z "$format_locale" ]]; then format_locale="$language_locale" else format_locale="${format_locale}.UTF-8" fi

Prompt user for keyboard layout

read -p "${bold}Enter your keyboard layout (e.g., us, de, fr): ${normal}" keylayout keylayout=$(validate_input "$keylayout" "Enter your keyboard layout: ") loadkeys "$keylayout"

Prompt user for root password and user account

read -s -p "${bold}Enter the root password: ${normal}" root_password echo "" read -p "${bold}Enter the username for the new user account: ${normal}" username username=$(validate_input "$username" "Enter the username for the new user account: ") read -s -p "${bold}Enter the password for the $username account: ${normal}" user_password echo ""

Disk setup

lsblk -e 7,11 echo "" read -p "${bold}Enter the disk to partition (e.g., sda or nvme0n1): ${normal}" disk base_disk=$(validate_input "$disk" "Enter the disk to partition: ") cfdisk "/dev/$base_disk"

Prompt user for partitions

read -p "${bold}Enter the partition number for EFI system partition (e.g., 1): ${normal}" efi_part efi_part=$(validate_input "$efi_part" "Enter the partition number for EFI system partition: ") read -p "${bold}Enter the partition number for BTRFS partition (e.g., 2): ${normal}" btrfs_part btrfs_part=$(validate_input "$btrfs_part" "Enter the partition number for BTRFS partition: ") read -p "${bold}Did you create a swap partition? (yes/no): ${normal}" created_swap if [[ "$created_swap" == "yes" ]]; then read -p "${bold}Enter the partition number for swap (e.g., 3): ${normal}" swap_part swap_part=$(validate_input "$swap_part" "Enter the partition number for swap: ") fi

Handle NVMe naming

if [[ "$base_disk" =~ ^nvme ]]; then efi_part="/dev/${base_disk}p${efi_part}" btrfs_part="/dev/${base_disk}p${btrfs_part}" if [[ "$created_swap" == "yes" ]]; then swap_part="/dev/${base_disk}p${swap_part}" fi else efi_part="/dev/${base_disk}${efi_part}" btrfs_part="/dev/${base_disk}${btrfs_part}" if [[ "$created_swap" == "yes" ]]; then swap_part="/dev/${base_disk}${swap_part}" fi fi

Format partitions and set labels

echo "${bold}${yellow}Wiping existing filesystem signatures...${normal}" wipefs -a "$efi_part" wipefs -a "$btrfs_part" if [[ "$created_swap" == "yes" ]]; then wipefs -a "$swap_part" fi

echo "${bold}${yellow}Formatting partitions...${normal}" mkfs.fat -F32 -n "EFI" "$efi_part" mkfs.btrfs -f -L "ROOT" "$btrfs_part" if [[ "$created_swap" == "yes" ]]; then mkswap -f -L "SWAP" "$swap_part" swapon "$swap_part" fi

Mount and create BTRFS subvolumes

mount "$btrfs_part" /mnt btrfs subvolume create /mnt/@ btrfs subvolume create /mnt/@cache btrfs subvolume create /mnt/@log btrfs subvolume create /mnt/@tmp btrfs subvolume create /mnt/@home btrfs subvolume create /mnt/@home_snapshots btrfs subvolume create /mnt/@snapshots umount /mnt

Remount with subvolumes

mount -o noatime,compress=zstd,space_cache=v2,subvol=@ "$btrfs_part" /mnt mkdir -p /mnt/{boot/efi,var/cache,var/log,tmp,home/.snapshots,.snapshots} mount -o noatime,compress=zstd,space_cache=v2,subvol=@cache "$btrfs_part" /mnt/var/cache mount -o noatime,compress=zstd,space_cache=v2,subvol=@log "$btrfs_part" /mnt/var/log mount -o noatime,compress=zstd,space_cache=v2,subvol=@tmp "$btrfs_part" /mnt/tmp mount -o noatime,compress=zstd,space_cache=v2,subvol=@home "$btrfs_part" /mnt/home mount -o noatime,compress=zstd,space_cache=v2,subvol=@home_snapshots "$btrfs_part" /mnt/home/.snapshots mount -o noatime,compress=zstd,space_cache=v2,subvol=@snapshots "$btrfs_part" /mnt/.snapshots mount "$efi_part" /mnt/boot/efi

Base package installation

base_packages="base linux-zen linux-zen-headers linux-firmware btrfs-progs grub grub-btrfs efibootmgr os-prober networkmanager nano git neofetch zsh zsh-completions zsh-autosuggestions openssh man sudo htop btop snapper" echo "${bold}Base packages: ${base_packages}${normal}" read -p "${bold}Enter any additional packages to install (space-separated): ${normal}" extra_packages pacstrap /mnt $base_packages $extra_packages

Generate fstab

genfstab -U /mnt >> /mnt/etc/fstab

Chroot and configuration

arch-chroot /mnt /bin/bash <<EOF ln -sf /usr/share/zoneinfo/$timezone /etc/localtime hwclock --systohc

Enable locales

for locale in $locales; do grep -q "^$locale" /etc/locale.gen || sed -i "/^#.*$locale/s/^#//" /etc/locale.gen done locale-gen

echo "LANG=$language_locale" > /etc/locale.conf echo "LC_TIME=$format_locale" >> /etc/locale.conf echo "KEYMAP=$keylayout" > /etc/vconsole.conf

echo "$hostname" > /etc/hostname echo "127.0.0.1   localhost" >> /etc/hosts echo "::1         localhost" >> /etc/hosts echo "127.0.1.1   $hostname.localdomain $hostname" >> /etc/hosts

echo "root:$root_password" | chpasswd useradd -m -G wheel -s /usr/bin/zsh "$username" echo "$username:$user_password" | chpasswd

echo "%wheel	ALL=(ALL) ALL" >> /etc/sudoers

systemctl enable NetworkManager sshd

snapper --config root create-config / snapper --config home create-config /home chmod a+rx /.snapshots chmod a+rx /home/.snapshots

grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB echo "GRUB_DISABLE_OS_PROBER=false" >> /etc/default/grub grub-mkconfig -o /boot/grub/grub.cfg

sudo pacman -S --needed --noconfirm git base-devel su - $username <<EOC git clone https://aur.archlinux.org/yay-bin.git cd yay-bin makepkg -si --noconfirm cd .. rm -rf yay-bin #yay -S --noconfirm zsh-theme-powerlevel10k-git #echo 'source /usr/share/zsh-theme-powerlevel10k/powerlevel10k.zsh-theme' >>~/.zshrc EOC EOF

read -p "${bold}${green}Installation complete! Do you want to reboot? (yes/no): ${normal}" reboot if [[ "$reboot" == "yes" ]]; then echo "${bold}Goodbye, rebooting in 5 seconds!" sleep 5 reboot else echo "${bold}Goodbye!" fi


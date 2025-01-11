#!/bin/bash

echo "Welcome to fluffy's base system install script!";
echo "Make sure the System is connected to the Internet"

# Ask for hostname
echo ""
echo "What will be the Hostname of this System? "
read -p "Hostname: " hostname

# Ask for disk
echo ""
fdisk -l
echo "On which disk should the installation take place? "
read -p "Disk (e.g., /dev/sda): " disk

# Set hostname
echo "$hostname" > /mnt/etc/hostname
echo "127.0.1.1   $hostname.localdomain   $hostname" >> /mnt/etc/hosts

# Set up partitions
echo ""
echo "Did you create the necessary partitions (root, home, swap)? (yes/no)"
read -p "Partition setup: " partition_check

if [[ "$partition_check" == "yes" ]]; then
    # Assuming partitions are already created using cfdisk
    echo "Enter the partition numbers (e.g., /dev/sda1): "
    read -p "Root partition: " root_partition
    read -p "Home partition (optional): " home_partition
    read -p "Swap partition (optional): " swap_partition
else
    echo "You must create the necessary partitions first using cfdisk."
    exit 1
fi

# Format partitions
echo "Formatting partitions..."
mkfs.btrfs $root_partition
mount $root_partition /mnt

# Create subvolumes for Btrfs (using the Btrfs layout as per guide)
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@snapshots

# Mount subvolumes
umount /mnt
mount -o subvol=@ $root_partition /mnt
mkdir /mnt/home
mount -o subvol=@home $root_partition /mnt/home
mkdir /mnt/.snapshots
mount -o subvol=@snapshots $root_partition /mnt/.snapshots

# Set up swap (if applicable)
if [[ -n "$swap_partition" ]]; then
    mkswap $swap_partition
    swapon $swap_partition
fi

# Install base system
pacstrap /mnt base linux-zen linux-zen-headers linux-firmware btrfs-progs grub efibootmgr os-prober networkmanager nano git neofetch zsh zsh-completions zsh-autosuggestions openssh man sudo snapper

# Install yay, snapper, snap-pac, grub-btrfs
arch-chroot /mnt /bin/bash -c "pacman -S yay --noconfirm"
arch-chroot /mnt /bin/bash -c "pacman -S snapper --noconfirm"
arch-chroot /mnt /bin/bash -c "yay -S snap-pac --noconfirm"
arch-chroot /mnt /bin/bash -c "yay -S grub-btrfs --noconfirm"

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

# Enable snapper service to handle Btrfs snapshots
arch-chroot /mnt /bin/bash -c "systemctl enable snapper-timeline.timer"
arch-chroot /mnt /bin/bash -c "systemctl enable snapper-cleanup.timer"

# Set up user account and password
echo ""
read -p "Enter the root password: " root_password
echo "root:$root_password" | arch-chroot /mnt chpasswd

read -p "Enter the username for your account: " username
read -p "Enter the password for your account: " user_password
arch-chroot /mnt useradd -m -G wheel -s /bin/zsh $username
echo "$username:$user_password" | arch-chroot /mnt chpasswd

# Enable NetworkManager service
arch-chroot /mnt /bin/bash -c "systemctl enable NetworkManager"

# Set up GRUB
arch-chroot /mnt /bin/bash -c "grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB"
arch-chroot /mnt /bin/bash -c "grub-mkconfig -o /boot/grub/grub.cfg"

# Enable GRUB Btrfs integration
arch-chroot /mnt /bin/bash -c "grub-btrfs install"

# Optionally install Oh My Zsh for all users
read -p "Do you want to install Oh My Zsh for all users? (yes/no): " install_omz
if [[ "$install_omz" == "yes" ]]; then
    arch-chroot /mnt /bin/bash -c "sh -c \"\$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)\" --unattended"
fi

# Reboot the system
echo "Installation complete. You can now reboot the system."

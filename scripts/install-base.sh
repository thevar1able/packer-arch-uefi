#!/usr/bin/env bash

# stop on errors
set -eu

DISK='/dev/vda'

FQDN='i-have-no-name'
KEYMAP='us'
LANGUAGE='en_US.UTF-8'
PASSWORD=$(/usr/bin/openssl passwd -crypt 'changeme')
TIMEZONE='UTC'

CONFIG_SCRIPT='/usr/local/bin/arch-config.sh'
BOOT_PARTITION="${DISK}1"
ROOT_PARTITION="${DISK}2"
TARGET_DIR='/mnt'
COUNTRY=${COUNTRY:-US}
MIRRORLIST="https://www.archlinux.org/mirrorlist/?country=${COUNTRY}&protocol=https&ip_version=4&use_mirror_status=on"

echo "==> Setting local mirror"
curl -s "$MIRRORLIST" |  sed 's/^#Server/Server/' > /etc/pacman.d/mirrorlist

echo "==> Clearing partition table on ${DISK}"
/usr/bin/sgdisk --zap ${DISK}

echo "==> Destroying magic strings and signatures on ${DISK}"
/usr/bin/dd if=/dev/zero of=${DISK} bs=512 count=2048
/usr/bin/wipefs --all ${DISK}

echo "==> Creating EFI /boot partition on ${DISK}"
/usr/bin/sgdisk --new=1:0:+256M -t 1:ef00 ${DISK}

echo "==> Creating /root partition on ${DISK}"
/usr/bin/sgdisk --new=2:0:0 ${DISK}

echo '==> Creating /boot filesystem (FAT32)'
/usr/bin/mkfs.fat -F32 ${BOOT_PARTITION}

echo '==> Creating /root filesystem (ext4)'
/usr/bin/mkfs.ext4 -O ^64bit -F -m 0 -q -L root ${ROOT_PARTITION}

echo "==> Mounting ${ROOT_PARTITION} to ${TARGET_DIR}"
/usr/bin/mount -o noatime,errors=remount-ro ${ROOT_PARTITION} ${TARGET_DIR}

echo "==> Mounting ${BOOT_PARTITION} to ${TARGET_DIR}/boot"
/usr/bin/mkdir ${TARGET_DIR}/boot
/usr/bin/mount ${BOOT_PARTITION} ${TARGET_DIR}/boot

echo '==> Bootstrapping the base installation'
/usr/bin/pacstrap ${TARGET_DIR} base base-devel
/usr/bin/arch-chroot ${TARGET_DIR} pacman -S --noconfirm gptfdisk openssh

echo '==> Generating the filesystem table'
/usr/bin/genfstab -p ${TARGET_DIR} >> "${TARGET_DIR}/etc/fstab"

echo '==> Generating the system configuration script'
/usr/bin/install --mode=0755 /dev/null "${TARGET_DIR}${CONFIG_SCRIPT}"

cat <<-EOF > "${TARGET_DIR}${CONFIG_SCRIPT}"
	echo '${FQDN}' > /etc/hostname
	/usr/bin/ln -s /usr/share/zoneinfo/${TIMEZONE} /etc/localtime
	echo 'KEYMAP=${KEYMAP}' > /etc/vconsole.conf
	/usr/bin/sed -i 's/#${LANGUAGE}/${LANGUAGE}/' /etc/locale.gen
	/usr/bin/locale-gen
	/usr/bin/mkinitcpio -p linux
	/usr/bin/usermod --password ${PASSWORD} root
	# https://wiki.archlinux.org/index.php/Network_Configuration#Device_names
	/usr/bin/ln -s /dev/null /etc/udev/rules.d/80-net-setup-link.rules
	/usr/bin/ln -s '/usr/lib/systemd/system/dhcpcd@.service' '/etc/systemd/system/multi-user.target.wants/dhcpcd@eth0.service'
	/usr/bin/sed -i 's/#UseDNS yes/UseDNS no/' /etc/ssh/sshd_config
	/usr/bin/sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config
	/usr/bin/systemctl enable sshd.service

	# Installing the bootloader
	bootctl install
	echo "default arch" > /boot/loader/loader.conf
	echo "timeout 1" >> /boot/loader/loader.conf

	# Configuring 'Arch Linux' boot entry
	cat <<-BOOTDOC > /boot/loader/entries/arch.conf
	title Arch Linux
	linux /vmlinuz-linux
	initrd /initramfs-linux.img
	options root=LABEL=root rw
	BOOTDOC

	# clean up
	/usr/bin/pacman -Rcns --noconfirm gptfdisk
EOF

echo '==> Entering chroot and configuring system'
/usr/bin/arch-chroot ${TARGET_DIR} ${CONFIG_SCRIPT}
rm "${TARGET_DIR}${CONFIG_SCRIPT}"

echo '==> Installation complete!'
/usr/bin/sleep 5
/usr/bin/umount ${TARGET_DIR}/boot
/usr/bin/umount ${TARGET_DIR}
/usr/bin/systemctl reboot

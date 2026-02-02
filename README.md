# Void linux + Framework 13 AMD 7040 + Full Disk Encryption + TMP2.0 + Xfce4

## Hardware
* Framework 13 
* AMD Ryzen 7 7840U
* 16GB RAM
* 1Tb SSD
* Dongle usb-c with ETH

## Preparation

Boot up [Void Linux ISO](https://voidlinux.org/download/) and do the following:
> [!WARNING]  
> Download iso live with XFCE4 

## Configuration file
All configuration and file modified are in src folder

## Boot by usb stick
Set correct keyboard layout

# Open XFCE4-terminal
```sh
sudo -i bash
```

### Check connectivity
```sh
ip addr
```
The command should return
```
2: enp195s0f3u1u4: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc fq_codel state UP group default qlen 1000
    link/ether XX:XX:XX:XX:XX:XX brd ff:ff:ff:ff:ff:ff
    inet 192.168.XXX.XXX/24 brd 192.168.12.255 scope global dynamic noprefixroute enp195s0f3u1u4
       valid_lft 86395sec preferred_lft 86395sec
	   ...
```
```sh
ping voidlinux.org
```

### Disk partitioning
I keep /home dir in separate partition and i would like set the disk like this:  
1 EFI   1Gb  
2 /	99Gb  
3 /home 850Gb  

```sh
fdisk /dev/nvme0n1
```
With the following sequence of characters we will obtain the desired partitioning (I assume the disk has 512 byte sectors): 
 - Command: g
 - Command: n
 - Partition number: <enter>
 - First sector: <enter>
 - Last sector ...: +1G
 - Command: t
 - Partition type or alias: 1 _(set EFI type it's very important)_
 - Command: n
 - Partition number: <enter>
 - First sector: <enter>
 - Last sector ...: +99G
 - Command: n
 - Partition number: <enter>
 - First sector: <enter>
 - Last sector ...: <enter>
 - Command: p (check if all partition have a right dimensioning)
 - Command: w

To set the first EFI partition when fdisk is still open:   
 - t
 - 1
 - 1
 - w

### Format EFI partition
```sh
mkfs.fat -F32 -n BOOT /dev/nvme0n1p1
```
### Encrypt and format root partition
```sh
cryptsetup luksFormat -h sha256 /dev/nvme0n1p2
cryptsetup open /dev/nvme0n1p2 root
mkfs.ext4 -L root /dev/mapper/root
```

### Encrypt and format home partition
```sh
cryptsetup luksFormat -h sha256 /dev/nvme0n1p3
cryptsetup open /dev/nvme0n1p3 home
mkfs.ext4 -L home /dev/mapper/home
```

### Mount partitions
```sh
mount /dev/mapper/root /mnt
mkdir /mnt/{boot,home}
mount /dev/nvme0n1p1 /mnt/boot
mount /dev/mapper/home /mnt/home
```

### Copy key
```sh
mkdir -p /mnt/var/db/xbps/keys
cp /var/db/xbps/keys/* /mnt/var/db/xbps/keys/
```

### Install minimal system
```sh
xbps-install -Sy -R https://repo-default.voidlinux.org/current -r /mnt base-container linux-mainline linux-mainline-headers linux-firmware-broadcom bash linux-firmware-amd linux-firmware-network mc vim cpio kpartx kmod eudev ncurses kbd NetworkManager sudo dbus cryptsetup iputils exfatprogs e2fsprogs hwinfo grub-x86_64-efi
```

### Create fstab
```sh
xgenfstab /mnt > /mnt/etc/fstab
```

## Chroot
```sh
xchroot /mnt bash
chown root:root /
chmod 755 /
passwd
```

### Set localtime
```sh
ln -sf /usr/share/zoneinfo/Europe/Rome /etc/localtime
```

### Set hostname
```sh
echo void-linux > /etc/hostname
```

```sh
mcedit /etc/hosts
```
modify:  
    127.0.0.1		localhost.localdomain	localhost	void-linux  
    ::1			localhost.localdomain	localhost ip6-localhost	void-linux  

### Set locale
```sh
echo "LANG=en_GB.UTF-8" > /etc/locale.conf
echo "en_US.UTF-8 UTF-8" >> /etc/default/libc-locales

```
if you need some more complex configuration see [src/etc/locale.conf](src/etc/locale.conf)

```sh
xbps-reconfigure -f glibc-locales
```

### Add user
```sh
useradd -mG wheel,lp,audio,video,optical,storage,dbus,input,plugdev,polkitd johndoe
passwd johndoe
```

```sh
mcedit /etc/sudoers.d/johndoe
```
add:  
    johndoe	ALL=(ALL:ALL) ALL

### Configure regional variable
```sh
mcedit /etc/rc.conf
```
add:  
	HARDWARECLOCK="UTC"  
	TIMEZONE="Europe/Rome"  
	KEYMAP="it"  

### Create volume key
```sh
dd bs=1 count=64 if=/dev/urandom of=/boot/volume.key
cryptsetup luksAddKey /dev/nvme0n1p2 /boot/volume.key
cryptsetup luksAddKey /dev/nvme0n1p3 /boot/volume.key
```

### Get UUID
```sh
blkid -s UUID -o value /dev/nvme0n1p2
blkid -s UUID -o value /dev/nvme0n1p3
```
from now the value returned from /dev/nvme0n1p2 will be <UUID_ROOT_PARTITION>  
from now the value returned from /dev/nvme0n1p3 will be <UUID_HOME_PARTITION>  

example:

UUID_ROOT_PARTITION=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx  
UUID_HOME_PARTITION=yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy

### Define crypttab
```sh
mcedit /etc/crypttab
```
add:  
    root UUID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx /boot/volume.key luks,discard  
    home UUID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx /boot/volume.key luks,discard  

### Configure NetworkManager
```sh
mcedit /etc/NetworkManager/NetworkManager.conf 
```
add: 
    [main]  
    plugins=keyfile  
    dns=default  
    rc-manager=resolvconf  

```sh
ln -s /etc/sv/NetworkManager /var/service
```

### Configure grub
```sh
mcedit /etc/default/grub
```
modify:  
    GRUB_CMDLINE_LINUX_DEFAULT="rd.luks.uuid=<UUID_ROOT_PARTITION> root=/dev/mapper/root  rd.luks.uuid=<UUID_HOME_PARTITION> home=/dev/mapper/home lsm=landlock,lockdown,yama,integrity,apparmor,bpf acpi_osi=\"!Windows 2000\" amdgpu.sg_display=0 nowatchdog net.ifnames=0 apparmor=1 security=apparmor rd.luks.allow=discards rw quiet rd.vconsole.keymap=it rd.retry=10"

### Configure dracut
```sh
mcedit /etc/dracut.conf.d/10-crypt.conf
```
add:  
    install_items+=" /boot/volume.key /etc/crypttab "
	add_dracutmodules+=" crypt "

### Finalize
```sh
xbps-reconfigure -f grub
dracut --force --regenerate-all
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=void
grub-mkconfig -o /boot/grub/grub.cfg
xbps-reconfigure -fa
```

## Try to reboot!!!
And login as root

### Remove unused firmware
```sh
mcedit /etc/xbps.d/linux-firmware.conf
```
add:  
    ignorepkg=linux-firmware-intel  
    ignorepkg=linux-firmware-nvidia  
```sh
xbps-remove -Ry linux-firmware-intel 
xbps-remove -Ry linux-firmware-nvidia  
```

### Install and enable base services 
```sh 
xbps-install -Su 
xbps-install logrotate cronie ufw smartmontools power-profiles-daemon polkit openntpd elogind dbus rsyslog
ln -s /etc/sv/crond /var/service
ln -s /etc/sv/dbus /var/service
ln -s /etc/sv/elogind /var/service
ln -s /etc/sv/nanoklogd /var/service
ln -s /etc/sv/ntpd /var/service
ln -s /etc/sv/polkitd /var/service
ln -s /etc/sv/power-profiles-daemon /var/service
ln -s /etc/sv/rsyslogd /var/service
ln -s /etc/sv/rtkit /var/service
ln -s /etc/sv/smartd  /var/service
ln -s /etc/sv/udevd  /var/service
ln -s /etc/sv/ufw  /var/service
```

### Install system notification error
```sh 
mcedit /usr/local/bin/sendmail-fake.sh
```
insert:  
    #!/bin/bash
    # /usr/local/bin/sendmail-fake.sh

    MESSAGE=$(cat)

    notify-send -t 5000 "Sendmail message" "$MESSAGE" --icon=dialog-information

    exit 0

```sh
chmod o+x /usr/local/bin/sendmail-fake.sh
ln -s /usr/local/bin/sendmail-fake.sh /usr/bin/sendmail
```

### Set S.M.A.R.T notify 
```sh
mcedit /usr/local/bin/smartdnotify
```
insert:  
    #!/bin/sh

    sudo -u johndoe DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus notify-send "S.M.A.R.T Error ($SMARTD_FAILTYPE)" "$SMARTD_MESSAGE" --icon=dialog-warning -u critical

```sh
chmod o+x /usr/local/bin/smartdnotify
```

```sh
mcedit /etc/smartd/smartd.conf
```
insert at the end:  
    DEVICESCAN -H -l error -l selftest -m root -M exec /usr/local/bin/smartdnotify



### Install bluetooth
```sh
xbps-install -Su bluez bluez-alsa
ln -s /etc/sv/bluetoothd /var/service
```

### Install XFCE4 
```sh
mcedit /etc/xbps.d/xfce4.conf 
```
add:  
    ignorepkg=mousepad  
    ignorepkg=ristretto  
    ignorepkg=parole  
    ignorepkg=xfce4-taskmanager  
    ignorepkg=ffplay6  
    ignorepkg=tumbler  

```sh
xbps-install vulkan-loader amdvlk mesa-vaapi mesa-vdpau xorg-minimal xf86-video-amdgpu xterm xorg-fonts xfce4 catfish xfce-polkit xfce4-pulseaudio-plugin xfce4-whiskermenu-plugin pavucontrol pulseaudio gvfs-smb lightdm lightdm-gtk3-greeter 
```

#### Install fprintd
```sh
xbps-install fprintd
```
Insert a row after #@include common-auth or at the beginning of the auth section:  
    auth	   sufficient pam_fprintd.so
for this files:
* /etc/pam.d/lightdm
* /etc/pam.d/system-auth
* /etc/pam.d/system-login

## Enable TPM2
If you want to enable decrypt from TPM2 follow this [TPM2-Documentation.md](TPM2-Documentation.md) and remember to delete /boot/volume.key 

## Resources
All modified files are in the src folder of this project.


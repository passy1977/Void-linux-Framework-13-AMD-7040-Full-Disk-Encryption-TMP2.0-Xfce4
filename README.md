# Void linux + Framework 13 AMD 7040 + Full Disk Encryption + TMP2.0 + Xfce4

## Hardware

- Framework 13

- AMD Ryzen 7 7840U

- 16GB RAM

- 1Tb SSD

- Dongle usb-c with ETH

## Preparation

Boot up [Void Linux ISO](https://voidlinux.org/download/) and do the following:

> \[!WARNING\]  
Download iso live with XFCE4

## Configuration file

All configuration and file modified are in src folder

## Boot by usb stick

Set correct keyboard layout

# Open XFCE4-terminal

```
sudo -i bash
```

### Check connectivity

```
ip addr
```

The command should return

```
2: enp195s0f3u1u4: \<BROADCAST,MULTICAST,UP,LOWER\_UP\> mtu 1500 qdisc fq\_codel state UP group default qlen 1000  
    link/ether XX:XX:XX:XX:XX:XX brd ff:ff:ff:ff:ff:ff  
    inet 192.168.XXX.XXX/24 brd 192.168.12.255 scope global dynamic noprefixroute enp195s0f3u1u4  
       valid\_lft 86395sec preferred\_lft 86395sec  
       ...

ping voidlinux.org
```

### Disk partitioning

I keep /home dir in separate partition and i would like set the disk like this:  
1 EFI   1Gb  
2 /	99Gb  
3 /home 850Gb

```
fdisk /dev/nvme0n1
```

With the following sequence of characters we will obtain the desired partitioning (I assume the disk has 512 byte sectors):

- Command: g

- Command: n

- Partition number: 

- First sector: 

- Last sector ...: +1G

- Command: t

- Partition type or alias: 1 *(set EFI type it's very important)*

- Command: n

- Partition number: 

- First sector: 

- Last sector ...: +99G

- Command: n

- Partition number: 

- First sector: 

- Last sector ...: 

- Command: p (check if all partition have a right dimensioning)

- Command: w

To set the first EFI partition when fdisk is still open:

- t

- 1

- 1

- w

### Format EFI partition

```
mkfs.fat -F32 -n BOOT /dev/nvme0n1p1
```

### Encrypt and format root partition

```
cryptsetup luksFormat -h sha256 /dev/nvme0n1p2  
cryptsetup open /dev/nvme0n1p2 root  
mkfs.ext4 -L root /dev/mapper/root
```

### Encrypt and format home partition

```
cryptsetup luksFormat -h sha256 /dev/nvme0n1p3  
cryptsetup open /dev/nvme0n1p3 home  
mkfs.ext4 -L home /dev/mapper/home
```

### Mount partitions

```
mount /dev/mapper/root /mnt  
mkdir /mnt/\{boot,home\}  
mount /dev/nvme0n1p1 /mnt/boot  
mount /dev/mapper/home /mnt/home
```

### Copy key

```
mkdir -p /mnt/var/db/xbps/keys  
cp /var/db/xbps/keys/\* /mnt/var/db/xbps/keys/
```

### Install minimal system

```
xbps-install -Sy -R https://repo-default.voidlinux.org/current -r /mnt base-container linux-mainline linux-mainline-headers linux-firmware-broadcom bash linux-firmware-amd linux-firmware-network mc vim cpio kpartx kmod eudev ncurses kbd NetworkManager sudo dbus cryptsetup iputils exfatprogs e2fsprogs hwinfo grub-x86\_64-efi
```

### Create fstab

```
xgenfstab /mnt \> /mnt/etc/fstab

mcedit /etc/hosts
```

add to /boot options umask=0077 like this:  
rw,discard,fmask=0022,dmask=0022,**umask=0077**,codepage=437,iocharset=iso8859-1,shortname=mixed,utf8,errors=remount-ro

## Chroot

```
xchroot /mnt bash  
chown root:root /  
chmod 755 /  
passwd
```

### Set localtime

```
ln -sf /usr/share/zoneinfo/Europe/Rome /etc/localtime
```

### Set hostname

```
echo void-linux \> /etc/hostname

mcedit /etc/hosts
```

modify:  
127.0.0.1		localhost.localdomain	localhost	void-linux  
::1			localhost.localdomain	localhost ip6-localhost	void-linux

### Set locale

```
echo "LANG=en\_GB.UTF-8" \> /etc/locale.conf  
echo "en\_US.UTF-8 UTF-8" \>\> /etc/default/libc-locales
```

if you need some more complex configuration see [src/etc/locale.conf](file:///home/antoniosalsi/projects/Void-linux-Framework-13-AMD-7040-Full-Disk-Encryption-TMP2.0-Xfce4/src/etc/locale.conf)

```
xbps-reconfigure -f glibc-locales
```

### Add user

```
useradd -mG wheel,lp,audio,video,optical,storage,dbus,input,plugdev,polkitd johndoe  
passwd johndoe

mcedit /etc/sudoers.d/johndoe
```

add:  
johndoe	ALL=(ALL:ALL) ALL

### Configure regional variable

```
mcedit /etc/rc.conf
```

add:  
HARDWARECLOCK="UTC"  
TIMEZONE="Europe/Rome"  
KEYMAP="it"

### Create volume key

```
dd bs=1 count=32 if=/dev/urandom of=/boot/volume.key  
cryptsetup luksAddKey /dev/nvme0n1p2 /boot/volume.key  
cryptsetup luksAddKey /dev/nvme0n1p3 /boot/volume.key
```

### Get UUID

```
blkid -s UUID -o value /dev/nvme0n1p2  
blkid -s UUID -o value /dev/nvme0n1p3
```

from now the value returned from /dev/nvme0n1p2 will be xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx  
from now the value returned from /dev/nvme0n1p3 will be yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy

example: UUID\_ROOT\_PARTITION=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx  
UUID\_HOME\_PARTITION=yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy

### Define crypttab

```
mcedit /etc/crypttab
```

add:  
root UUID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx /boot/volume.key luks,discard  
home UUID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx /boot/volume.key luks,discard

### Configure NetworkManager

```
mcedit /etc/NetworkManager/NetworkManager.conf 
```

add: \[main\]  
plugins=keyfile  
dns=default  
rc-manager=resolvconf

```
ln -s /etc/sv/NetworkManager /var/service
```

### Configure grub

```
mcedit /etc/default/grub
```

modify:  
GRUB\_CMDLINE\_LINUX\_DEFAULT="rd.luks.uuid=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx root=/dev/mapper/root  rd.luks.uuid=yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy home=/dev/mapper/home lsm=landlock,lockdown,yama,integrity,apparmor,bpf acpi\_osi="!Windows 2000" amdgpu.sg\_display=0 nowatchdog net.ifnames=0 apparmor=1 security=apparmor rd.luks.allow=discard rw quiet rd.vconsole.keymap=it rd.retry=10"

### Configure dracut

```
mcedit /etc/dracut.conf.d/10-crypt.conf
```

add:  
install\_items+=" /boot/volume.key /etc/crypttab " add\_dracutmodules+=" crypt " kernel\_cmdline+=" rd.luks.allow-discards "

### Finalize

```
xbps-reconfigure -f grub  
dracut --force --regenerate-all  
grub-install --target=x86\_64-efi --efi-directory=/boot --bootloader-id=void  
grub-mkconfig -o /boot/grub/grub.cfg  
xbps-reconfigure -fa
```

## Try to reboot!!!

And login as root

### Add locale repository

```
echo 'repository=https://voidlinux.mirror.garr.it/current' \> /etc/xbps.d/10-repository-main.conf
```

### Remove unused firmware

```
mcedit /etc/xbps.d/linux-firmware.conf
```

add:  
ignorepkg=linux-firmware-intel  
ignorepkg=linux-firmware-nvidia

```
xbps-remove -Ry linux-firmware-intel   
xbps-remove -Ry linux-firmware-nvidia  
```

### Install and enable base services

elogin don't need to be linked to /var/service because it start with pid 1

```
xbps-install -Su   
xbps-install logrotate cronie ufw smartmontools power-profiles-daemon polkit openntpd elogind dbus apparmor  
ln -s /etc/sv/crond /var/service  
ln -s /etc/sv/dbus /var/service  
ln -s /etc/sv/nanoklogd /var/service  
ln -s /etc/sv/socklog-unix/ /var/service  
ln -s /etc/sv/ntpd /var/service  
ln -s /etc/sv/polkitd /var/service  
ln -s /etc/sv/power-profiles-daemon /var/service  
ln -s /etc/sv/rtkit /var/service  
ln -s /etc/sv/smartd  /var/service  
ln -s /etc/sv/udevd  /var/service  
ln -s /etc/sv/ufw  /var/service
```

### USB Disk defaulf mount

```
mcedit /etc/udev/rules.d/99-udisks2.rules
```

insert:  
ENV\{ID\_FS\_USAGE\}=="filesystem|other|crypto", ENV\{UDISKS\_FILESYSTEM\_SHARED\}="1"

### Enable zram

```
mcedit /etc/udev/rules.d/99-zram.rules
```

insert:  
ACTION=="add", KERNEL=="zram0", ATTR\{initstate\}=="0", ATTR\{comp\_algorithm\}="zstd", ATTR\{disksize\}="4G"

```
mcedit /etc/sysctl.conf
```

add:  
vm.swappiness=100

vm.page-cluster=0

```
mcedit /etc/rc.local
```

add:

```
    if \[ ! -e /dev/zram0 \]; then    
        echo "Initialize zram"    
        modprobe zram    
        echo 4G \> /sys/block/zram0/disksize    
        echo zstd \> /sys/block/zram0/comp\_algorithm    
        mkswap /dev/zram0    
        swapon --priority 100 /dev/zram0    
    else    
        \# Se esiste ma non è attivo, resetta e ricrea    
        if ! swapon --show | grep -q /dev/zram0; then    
        echo "Configure zram"    
            swapoff /dev/zram0 2\>/dev/null    
            mkswap /dev/zram0    
            swapon --priority 100 /dev/zram0    
        fi    
    fi  
```

### FSTrim nvme

```
mcedit /etc/cron.weekly/fstrim
```

insert:  
\#!/bin/bash  
fstrim / 2\>/dev/null || true 

fstrim /boot 2\>/dev/null || true 

fstrim /home 2\>/dev/null || true

```
chmod +x /etc/cron.weekly/fstrim
```

### Install system notification error

```
mcedit /usr/local/bin/sendmail-fake.sh
```

insert:

```
    \#!/bin/bash  
    \# /usr/local/bin/sendmail-fake.sh  
  
    MESSAGE=$(cat)  
  
    notify-send -t 5000 "Sendmail message" "$MESSAGE" --icon=dialog-information  
  
    exit 0

chmod o+x /usr/local/bin/sendmail-fake.sh  
ln -s /usr/local/bin/sendmail-fake.sh /usr/bin/sendmail
```

### Set S.M.A.R.T notify

```
mcedit /usr/local/bin/smartdnotify
```

insert:

```
    \#!/bin/sh  
  
    sudo -u johndoe DISPLAY=:0 DBUS\_SESSION\_BUS\_ADDRESS=unix:path=/run/user/1000/bus notify-send "S.M.A.R.T Error ($SMARTD\_FAILTYPE)" "$SMARTD\_MESSAGE" --icon=dialog-warning -u critical

chmod o+x /usr/local/bin/smartdnotify

mcedit /etc/smartd/smartd.conf
```

insert at the end:  
DEVICESCAN -H -l error -l selftest -m root -M exec /usr/local/bin/smartdnotify

### Configure hibernation

```
filefrag -v /var/swap.img
```

in the index 0 of ext: label get physical\_offset: value in my case

sudo filefrag -v /var/swap.img  
Place your finger on the fingerprint reader Filesystem type is: ef53  
File size of /var/swap.img is 17179869184 (4194304 blocks of 4096 bytes)  
ext:     logical\_offset:        physical\_offset: length:   expected: flags:  
0:        0..       0:      **43008**..     43008:      1:

```
mcedit /set/default/grub
```

add in tail of GRUB\_CMDLINE\_LINUX\_DEFAULT="... resume=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx resume\_offset=43008"

### Install bluetooth

```
xbps-install -Su bluez bluez-alsa  
ln -s /etc/sv/bluetoothd /var/service
```

### Install XFCE4

```
mcedit /etc/xbps.d/xfce4.conf 
```

add:  
ignorepkg=mousepad  
ignorepkg=ristretto  
ignorepkg=parole  
ignorepkg=xfce4-taskmanager  
ignorepkg=ffplay6  
ignorepkg=tumbler

```
xbps-install vulkan-loader amdvlk mesa-vaapi mesa-vdpau xorg-minimal xf86-video-amdgpu xterm xorg-fonts xfce4 catfish xfce-polkit xfce4-pulseaudio-plugin xfce4-whiskermenu-plugin pavucontrol pulseaudio gvfs-smb lightdm lightdm-gtk3-greeter xdg-desktop-portal-gtk 
```

### Install Flatpak

```
xbps-install flatpak  
sudo flatpak remote-add --if-not-exists --system flathub https://flathub.org/repo/flathub.flatpakrepo
```

### Install fprintd

```
xbps-install fprintd  
fprintd-enroll johndoe  
fprintd-enroll johndoe -f left-index-finger 
```

Insert a row after \#@include common-auth or at the beginning of the auth section:  
auth sufficient pam\_fprintd.so for this files:

- /etc/pam.d/lightdm

- /etc/pam.d/system-auth

- /etc/pam.d/system-login

### FIX apparmor="ALLOWED" operation="sendmsg" class="net" info="failed af match" error=-13 profile="pulseaudio" pid=2020 comm="bluetooth" family="bluetooth" sock\_type="seqpacket" protocol=0 requested\_mask="send" denied\_mask="send"

```
mcedit /etc/apparmor.d/usr.bin.pulseaudio
```

alter some *include\<...\>*  
add *network bluetooth,*  
something like that:

```
  ...  
  include \<abstractions/base\>  
  include \<abstractions/audio\>  
  include \<abstractions/dbus-session\>  
  include \<abstractions/dbus-strict\>  
  include \<abstractions/nameservice\>  
  include \<abstractions/X\>  
  
  network bluetooth,  
  
  dbus send  
  ...
```

### Enable restart xorg with ctr + alt + back

In this case I force Italian keyboard layout

```
cat /etc/X11/xorg.conf.d/00-keyboard.conf \<\< 'EOF'  
Section "InputClass"  
    Identifier "system-keyboard"  
    MatchIsKeyboard "yes"  
    Option "XkbLayout" "it"  
    Option "XkbModel" "pc105"  
    Option "XkbOptions" "terminate:ctrl\_alt\_bksp"  
EndSection  
EOF
```

### Enable TPM2

If you want to enable decrypt from TPM2 follow this [TPM2-Documentation.md](file:///home/antoniosalsi/projects/Void-linux-Framework-13-AMD-7040-Full-Disk-Encryption-TMP2.0-Xfce4/TPM2-Documentation.md) and remember to delete /boot/volume.key

## Resources

All modified files are in the src folder of this project.


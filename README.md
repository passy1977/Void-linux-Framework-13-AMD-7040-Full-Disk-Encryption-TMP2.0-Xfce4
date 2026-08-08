# Void linux + Framework 13 AMD 7040 + Full Disk Encryption + TMP2.0 + Xfce4

## Hardware

- Framework 13
- AMD Ryzen 7 7840U (_bios 3.20_)
- 16GB RAM
- 1Tb SSD
- Dongle usb-c with ETH

## Preparation

Boot up [Void Linux ISO](https://voidlinux.org/download/) and do the following:

> [!WARNING]  
> Download iso live with XFCE4 

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
2: enp195s0f3u1u4: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc fq_codel state UP group default qlen 1000  
    link/ether XX:XX:XX:XX:XX:XX brd ff:ff:ff:ff:ff:ff  
    inet 192.168.XXX.XXX/24 brd 192.168.12.255 scope global dynamic noprefixroute enp195s0f3u1u4  
       valid_lft 86395sec preferred_lft 86395sec  
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
mkdir /mnt/{boot,home}  
mount /dev/nvme0n1p1 /mnt/boot  
mount /dev/mapper/home /mnt/home
```

### Copy key

```
mkdir -p /mnt/var/db/xbps/keys  
cp /var/db/xbps/keys/* /mnt/var/db/xbps/keys/
```

### Install minimal system

```
xbps-install -Sy -R https://repo-default.voidlinux.org/current -r /mnt base-container linux-mainline linux-mainline-headers linux-firmware-broadcom bash linux-firmware-amd linux-firmware-network mc vim cpio kpartx kmod eudev ncurses kbd NetworkManager sudo dbus cryptsetup iputils exfatprogs e2fsprogs hwinfo grub-x86_64-efi
```

### Create fstab

```
xgenfstab /mnt > /mnt/etc/fstab

mcedit /etc/fstab
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
echo void-linux > /etc/hostname

mcedit /etc/hosts
```

modify:
```
127.0.0.1		localhost.localdomain	localhost	void-linux  
::1			localhost.localdomain	localhost ip6-localhost	void-linux
```

### Set locale

```
echo "LANG=en_GB.UTF-8" > /etc/locale.conf  
echo "en_US.UTF-8 UTF-8" >> /etc/default/libc-locales
```

if you need some more complex configuration see [src/etc/locale.conf](src/etc/locale.conf)

```
xbps-reconfigure -f glibc-locales
```

### Add user


```
cat /etc/skel/.bashrc << 'EOF'  
#
# ~/.bashrc
#

# If not running interactively, don't do anything
[[ $- != *i* ]] && return

# alias ls='ls --color=auto'
#PS1='[\u@\h \W]\$ '

#####

# set a fancy prompt (non-color, unless we know we "want" color)
case "$TERM" in
    xterm-color|*-256color) color_prompt=yes;;
esac


# uncomment for a colored prompt, if the terminal has the capability; turned
# off by default to not distract the user: the focus in a terminal window
# should be on the output of commands, not on the prompt
force_color_prompt=yes

if [ -n "$force_color_prompt" ]; then
    if [ -x /usr/bin/tput ] && tput setaf 1 >&/dev/null; then
	# We have color support; assume it's compliant with Ecma-48
	# (ISO/IEC-6429). (Lack of such support is extremely rare, and such
	# a case would tend to support setf rather than setaf.)
	color_prompt=yes
    else
	color_prompt=
    fi
fi

unset color_prompt force_color_prompt

# enable color support of ls and also add handy aliases
if [ -x /usr/bin/dircolors ]; then
    test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
    alias ls='ls --color=auto'
    alias dir='dir --color=auto'
    alias vdir='vdir --color=auto'

    alias grep='grep --color=auto'
    alias fgrep='fgrep --color=auto'
    alias egrep='egrep --color=auto'
fi

# colored GCC warnings and errors
export GCC_COLORS='error=01;31:warning=01;35:note=01;36:caret=01;32:locus=01:quote=01'

# Alias definitions.
# You may want to put all your additions into a separate file like
# ~/.bash_aliases, instead of adding them here directly.
# See /usr/share/doc/bash-doc/examples in the bash-doc package.

if [ -f ~/.bash_aliases ]; then
    . ~/.bash_aliases
fi

# enable programmable completion features (you don't need to enable
# this, if it's already enabled in /etc/bash.bashrc and /etc/profile
# sources /etc/bash.bashrc).
if ! shopt -oq posix; then
  if [ -f /usr/local/share/bash-completion/bash_completion ]; then
    . /usr/local/share/bash-completion/bash_completion
  elif [ -f /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
  elif [ -f /etc/bash_completion ]; then
    . /etc/bash_completion
  fi
fi

# Compatibility shim: bash-completion 2.x renamed _init_completion to _comp_initialize
if declare -f _comp_initialize > /dev/null && ! declare -f _init_completion > /dev/null; then
  _init_completion() { _comp_initialize "$@"; }
fi

# For the graphical elements
#export QT_SCALE_FACTOR=1.5 

# To make the fonts readable
#export QT_FONT_DPI=96

#export QT_AUTO_SCREEN_SCALE_FACTOR=1

export PS1="\[\033[01;32m\][\u@\h]\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ "

unset HISTFILESIZE
export HISTSIZE=10000
export HISTFILESIZE=10000
export HISTCONTROL=ignorespace:ignoredups
export HISTIGNORE="&:ls:ll:exit:[bf]g:history"
'EOF'

cat /etc/skel/.profile << 'EOF'  
# ~/.profile: executed by the command interpreter for login shells.
# This file is not read by bash(1), if ~/.bash_profile or ~/.bash_login
# exists.
# see /usr/share/doc/bash/examples/startup-files for examples.
# the files are located in the bash-doc package.

# the default umask is set in /etc/profile; for setting the umask
# for ssh logins, install and configure the libpam-umask package.
#umask 022

# if running bash
if [ -n "$BASH_VERSION" ]; then
    # include .bashrc if it exists
    if [ -f "$HOME/.bashrc" ]; then
	. "$HOME/.bashrc"
    fi
fi

# set PATH so it includes user's private bin if it exists
if [ -d "$HOME/bin" ] ; then
    PATH="$HOME/bin:$PATH"
fi

# set PATH so it includes user's private bin if it exists
if [ -d "$HOME/.local/bin" ] ; then
    PATH="$HOME/.local/bin:$PATH"
fi
'EOF'

useradd -mG wheel,lp,audio,video,optical,storage,dbus,input,plugdev,polkitd johndoe  
passwd johndoe

cat /etc/sudoers.d/johndoe << 'EOF'  
johndoe	ALL=(ALL:ALL) ALL
'EOF'
```

### Configure regional variable

```
cat /etc/rc.conf << 'EOF'   
#set hw rtc to UTC
HARDWARECLOCK="UTC"  

#set timezone
TIMEZONE="Europe/Rome"  

#set keymap 
KEYMAP="it"

#enable cgroup
CGROUP_MODE=unified
'EOF'
```

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

example: UUID_ROOT_PARTITION=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx  
UUID_HOME_PARTITION=yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy

### Define crypttab

```
cat /etc/crypttab << 'EOF'  
root UUID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx /boot/volume.key luks,discard  
home UUID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx /boot/volume.key luks,discard
'EOF'
```

### Configure NetworkManager

```
cat /etc/NetworkManager/NetworkManager.conf  << 'EOF'   
[main]
plugins=keyfile
dns=default
rc-manager=resolvconf
'EOF'

ln -s /etc/sv/NetworkManager /var/service
```

### Configure grub

```
mcedit /etc/default/grub
```

modify:  
~~GRUB_CMDLINE_LINUX_DEFAULT="rd.luks.uuid=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx root=/dev/mapper/root  rd.luks.uuid=yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy home=/dev/mapper/home lsm=landlock,lockdown,yama,integrity,apparmor,bpf acpi_osi="!Windows 2000" nowatchdog net.ifnames=0 apparmor=1 security=apparmor rw quiet rd.vconsole.keymap=it rd.retry=10 rd.luks.allow-discards resume=UUID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx resume_offset=zzzzz zswap.enabled=1 zswap.compressor=lz4 loglevel=4"~~
```
GRUB_CMDLINE_LINUX_DEFAULT="rd.luks.uuid=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx root=/dev/mapper/root  rd.luks.uuid=yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy home=/dev/mapper/home lsm=landlock,lockdown,yama,integrity,apparmor,bpf nowatchdog net.ifnames=0 apparmor=1 security=apparmor rw rd.vconsole.keymap=it rd.retry=10 rd.luks.allow-discards resume=UUID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx resume_offset=zzzzz zswap.enabled=1 zswap.compressor=lz4 quiet acpi=Linux"
```

### Configure dracut

```
mcedit /etc/dracut.conf.d/10-crypt.conf
```

add:  
install_items+=" /boot/volume.key /etc/crypttab " add_dracutmodules+=" crypt " kernel_cmdline+=" rd.luks.allow-discards "

### Finalize

```
xbps-reconfigure -f grub  
dracut --force --regenerate-all  
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=void  
grub-mkconfig -o /boot/grub/grub.cfg  
xbps-reconfigure -fa
```

## Try to reboot!!!

And login as root

### Add locale repository

```
echo 'repository=https://voidlinux.mirror.garr.it/current' > /etc/xbps.d/10-repository-main.conf
```

### Remove unused firmware

```
cat /etc/xbps.d/linux-firmware.conf  << 'EOF'   
ignorepkg=linux-firmware-intel  
ignorepkg=linux-firmware-nvidia
'EOF'

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
ENV{ID_FS_USAGE}=="filesystem|other|crypto", ENV{UDISKS_FILESYSTEM_SHARED}="1"

### ~~Enable zram~~


~~mcedit /etc/udev/rules.d/99-zram.rules~~


~~insert:~~  
~~ACTION=="add", KERNEL=="zram0", ATTR{initstate}=="0", ATTR{comp_algorithm}="zstd", ATTR{disksize}="4G"~~

~~mcedit /usr/local/lib/sysctl.d/99_zram.conf~~


~~add:~~  
~~vm.swappiness=90~~  
~~vm.page-cluster=0~~


~~mcedit /etc/rc.local~~

~~add:~~  
~~echo "033[1m=> Configure zram033[mn"~~  
~~swapoff /dev/zram0 2>/dev/null~~  
~~mkswap /dev/zram0~~  
~~swapon --priority 100 /dev/zram0~~  



### Swappiness
```
cat /usr/local/lib/sysctl.d/99_swappiness.conf  << 'EOF'   
vm.swappiness=90
vm.page-cluster=1
'EOF'
```

### Read ahead
When you read a file, the kernel reads extra data beyond what you asked for assuming you will need it next. This is called read-ahead. Measured in kilobytes.  
```
cat /etc/udev/rules.d/99-read-ahead.rules  << 'EOF'   
ACTION=="add|change", KERNEL=="nvme0n1", ATTR{queue/read_ahead_kb}="2048"
'EOF'
```

### Dirty pages

When you write a file, data goes to a memory buffer first (dirty pages) and is flushed to disk later. These two parameters control when that flushing happens.  
* __vm.dirty_ratio__ — maximum percentage of RAM that can contain dirty data before the kernel blocks new writes and forces a flush. Default is typically 20%.  
* __vm.dirty_background_ratio__ — percentage at which background flushing begins quietly, without blocking applications.  
```
cat /usr/local/lib/sysctl.d/99_dirty_pages.conf  << 'EOF'   
vm.dirty_ratio=10
vm.dirty_background_ratio=5
'EOF'
```

### Memory mapped

Maximum number of memory-mapped regions a single process is allowed to have. The default is conservative and causes silent failures in some workloads - Proton/Steam games, Elasticsearch, and large Java applications all hit this ceiling.
```
cat /usr/local/lib/sysctl.d/99_memory_mapped.conf  << 'EOF'   
vm.max_map_count=262144
'EOF'
```
### Scheduled auogroup

Autogroup changes how CPU time is distributed. Instead of treating every process equally, the kernel groups processes by terminal session. Each TTY session becomes a group and the scheduler gives equal time to each group - not to each individual process.

```
cat /usr/local/lib/sysctl.d/99_scheduled_auogroup.conf  << 'EOF'   
kernel.sched_autogroup_enabled=0
'EOF'
```

### FSTrim nvme

```
cat /etc/cron.weekly/fstrim << 'EOF'   
#!/bin/bash  
fstrim / 2>/dev/null || true   
fstrim /boot 2>/dev/null || true   
fstrim /home 2>/dev/null || true
'EOF'

chmod +x /etc/cron.weekly/fstrim
```

### Install system notification error

Copy [src/usr/local/bin/sendmail-fake](src/usr/local/bin/sendmail-fake) to /usr/local/bin

```
chmod o+x /usr/local/bin/sendmail-fake
ln -s /usr/local/bin/sendmail-fake /usr/bin/sendmail
```

### Set S.M.A.R.T notify

Copy [src/usr/local/bin/smartnotify](src/usr/local/bin/smartnotify) to /usr/local/bin

```
chmod o+x /usr/local/bin/smartnotify
```

```
mcedit /etc/smartd/smartd.conf
```
insert at the end:  
```
DEVICESCAN -H -l error -l selftest -m root -M exec /usr/local/bin/smartnotify
```

Enable monthly nmve self test
```
cat /etc/cron.monthly/smartd-self-test << 'EOF'   
#!/bin/sh

/usr/bin/smartctl -t short /dev/nvme0
'EOF'

chmod +x /etc/cron.monthly/smartd-self-test
```

### Create script for check runit status

```
cat /usr/local/bin/sv_ls << 'EOF'   
#!/bin/bash

USE_COLOR=true

print_help() {
    printf "Usage: %s [OPTION]\n" "$(basename "$0")"
    printf "\n"
    printf "Options:\n"
    printf "  -h, --help      Show this help message\n"
    printf "  -m, --monitor   Run in monitor mode using watch (no colors)\n"
    printf "  --no-color      No colors\n"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            print_help
            exit 0
            ;;
        -m|--monitor)
            exec watch -n 2 "$0" --no-color
            ;;
        --no-color)
            USE_COLOR=false
            shift
            ;;
        *)
            printf "Unknown option: %s\n" "$1" >&2
            print_help >&2
            exit 1
            ;;
    esac
done

if $USE_COLOR; then
    GREEN='\033[0;32m'
    BLUE='\033[0;36m'
    NC='\033[0m'
else
    GREEN=''
    BLUE=''
    NC=''
fi

printf "${BLUE}%-40s %-10s %-10s${NC}\n" "SERVICE" "PID" "UPTIME"
printf "%s\n" "------------------------------------------------------------"

sudo sv status /var/service/* | while IFS= read -r line; do

    if [[ $line =~ run:\ (/var/service/[^:]+): ]]; then
        service_path="${BASH_REMATCH[1]}"
        service_name=$(basename "$service_path")
    else
        continue 
    fi

    if [[ $line =~ \(pid\ ([0-9]+) ]]; then
        pid="${BASH_REMATCH[1]}"
    else
        pid="N/A"
    fi

    if [[ $line =~ \(pid\ [0-9]+\)\ ([0-9]+)s\; ]]; then
        uptime="${BASH_REMATCH[1]}s"
    else
        uptime="N/A"
    fi

    printf "${GREEN}%-40s %-10s %-10s${NC}\n" "$service_name" "$pid" "$uptime"
done

'EOF'
chmod o+x /usr/local/bin/sv_ls
```

### Configure hibernation

```
filefrag -v /var/swap.img
```

in the index 0 of ext: label get physical_offset: value in my case

sudo filefrag -v /var/swap.img  
Place your finger on the fingerprint reader Filesystem type is: ef53  
File size of /var/swap.img is 17179869184 (4194304 blocks of 4096 bytes)  
ext:     logical_offset:        physical_offset: length:   expected: flags:  
0:        0..       0:      **43008**..     43008:      1:

```
mcedit /set/default/grub
```

add in tail of GRUB_CMDLINE_LINUX_DEFAULT="... resume=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx resume_offset=43008"

### Install bluetooth

```
xbps-install -Su bluez bluez-alsa  
ln -s /etc/sv/bluetoothd /var/service
```

### Install XFCE4

```
cat /etc/xbps.d/xfce4.conf << 'EOF'   
ignorepkg=mousepad  
ignorepkg=ristretto  
ignorepkg=parole  
ignorepkg=xfce4-taskmanager  
ignorepkg=ffplay6  
ignorepkg=tumbler
'EOF'

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

Insert a row after #@include common-auth or at the beginning of the auth section:  
auth sufficient pam_fprintd.so for this files:

- /etc/pam.d/lightdm
- /etc/pam.d/system-auth
- /etc/pam.d/system-login

### FIX Aparmor error
if find into log an erro like that:  
_apparmor="ALLOWED" operation="sendmsg" class="net" info="failed af match" error=-13 profile="pulseaudio" pid=2020 comm="bluetooth" family="bluetooth" sock_type="seqpacket" protocol=0 requested_mask="send" denied_mask="send"_

```
mcedit /etc/apparmor.d/usr.bin.pulseaudio
```

alter some *include<...>*  
add *network bluetooth,*  
something like that:

```
  ...  
  include <abstractions/base>  
  include <abstractions/audio>  
  include <abstractions/dbus-session>  
  include <abstractions/dbus-strict>  
  include <abstractions/nameservice>  
  include <abstractions/X>
  
  network bluetooth,  
  
  dbus send  
  ...
```

### Enable restart xorg with ctr + alt + back

In this case I force Italian keyboard layout

```
cat /etc/X11/xorg.conf.d/00-keyboard.conf << 'EOF'  
Section "InputClass"  
    Identifier "system-keyboard"  
    MatchIsKeyboard "yes"  
    Option "XkbLayout" "it"  
    Option "XkbModel" "pc105"  
    Option "XkbOptions" "terminate:ctrl_alt_bksp"  
EndSection  
'EOF'
```

### Podman configuration
```
cat /etc/security/limits.d/johndoe-limits.conf << 'EOF'  
johndoe soft nofile 65536
johndoe hard nofile 65536
johndoe soft memlock unlimited
johndoe hard memlock unlimited
'EOF'
```
```
mcedit /etc/pam.d/lightdm
```
Add `session required pam_limits.so` to pam modules at the start of _\# Setup session_:
```
# Setup session
session   required pam_limits.so
...
```
```
mcedit /etc/pam.d/system-login
```
Add `session required pam_limits.so` to pam modules before _session    optional   pam_loginuid.so_:
```
session   required pam_limits.so
...
```
Enable efuse overlay

```
cat /etc/containers/storage.conf << 'EOF'  
[storage]
driver = "overlay"

[storage.options.overlay]
mount_program = "/usr/bin/fuse-overlayfs"
'EOF
```

~~Configure cgroup v2~~

~~sudo tee -a /etc/rc.local "EOF '~~
~~echo "\033[1m=> Configure cgroup v2\033[m\n"~~
~~echo "+cpu +memory +i0 +pids" /sys/fs/cgroup/~~cgroup. subtree_control~~
~~EOF~~

Use crun instead runc

```
echo "ignorepkg=runc" > /etc/xbps.d/podman.conf
```
Reboot the system

```
xbps-install -Su podman crun fuse-overlayfs
```
Check the configuration
```
podman info --format '{{.Host.OCIRuntime.Name}}'
```

### Enable TPM2

If you want to enable decrypt from TPM2 follow this [TPM2-Documentation.md](TPM2-Documentation.md) and remember to delete /boot/volume.key

## Resources

All modified files are in the src folder of this project.

## References
Many thanks to the [YouTuxChannel](https://www.youtube.com/@YouTuxChannel) to give me many tips to enforce my Void linux configuration [A Kernel Inside Your Kernel — Complete Technical Guide](https://youtux.org/Kernel%20Secrets.html#autogroup)

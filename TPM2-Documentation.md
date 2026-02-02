# TPM2 Automatic LUKS Unlock for Void Linux with runit

**Complete Technical Documentation**

---

## Table of Contents

1. [Overview](#overview)
2. [Problem Statement](#problem-statement)
3. [Solution Architecture](#solution-architecture)
4. [Prerequisites](#prerequisites)
5. [Implementation](#implementation)
6. [Scripts Created](#scripts-created)
7. [Boot Process](#boot-process)
8. [Testing & Verification](#testing--verification)
9. [Troubleshooting](#troubleshooting)
10. [Maintenance](#maintenance)
11. [Security Considerations](#security-considerations)

---

## Overview

This implementation provides automatic LUKS disk encryption unlock using TPM2 (Trusted Platform Module 2.0) on Void Linux with runit init system, **without using Clevis**.

### Key Features

- ✅ Automatic disk unlock at boot using TPM2
- ✅ Compatible with Void Linux + runit (non-systemd)
- ✅ PCR-based security (firmware, bootloader, secure boot)
- ✅ Fallback to manual password on failure
- ✅ Custom dracut module implementation
- ✅ No Clevis dependency

### System Information

- **Distribution**: Void Linux
- **Init System**: runit
- **Kernel**: 6.18.7_1 / 6.18.8_1
- **Boot Manager**: GRUB
- **Encryption**: LUKS1 (root), LUKS2 (home)

---

## Problem Statement

### Why Clevis Doesn't Work on Void Linux + runit

Clevis TPM2 automatic unlock is designed for **systemd-based systems**. On non-systemd systems like Void Linux with runit:

1. **Hook Timing Issue**: Clevis uses `initqueue/online` hook which waits for network events that never occur without systemd
2. **Missing Dependencies**: Clevis expects systemd units in initramfs
3. **Event Loop**: The unlock script waits indefinitely for events that are never triggered

**Result**: System hangs with `dracut Warning: Signal caught!` and timeout errors.

### Solution Approach

Implement a **custom dracut module** that:
- Uses TPM2 tools directly (no Clevis)
- Executes at the correct hook (`initqueue/settled`)
- Reconstructs TPM2 contexts from persistent `.pub`/`.priv` files
- Provides clear error messages and fallback

---

## Solution Architecture

### Components

```
┌─────────────────────────────────────────────────────────┐
│                    Boot Process                         │
├─────────────────────────────────────────────────────────┤
│ GRUB → Kernel → Initramfs                              │
│                     ↓                                   │
│         udev triggers device detection                  │
│                     ↓                                   │
│         initqueue/settled/60-tpm2-unlock.sh            │
│                     ↓                                   │
│         /usr/local/libexec/tpm2-unseal                 │
│                     ↓                                   │
│    ┌────────────────┴────────────────┐                 │
│    │  For each LUKS device:          │                 │
│    │  1. Load TPM2 primary key       │                 │
│    │  2. Load sealed object          │                 │
│    │  3. Unseal keyfile with PCR     │                 │
│    │  4. Unlock with cryptsetup      │                 │
│    └────────────────┬────────────────┘                 │
│                     ↓                                   │
│         Root filesystem mounted                         │
│                     ↓                                   │
│         switch_root → runit stage 1                    │
└─────────────────────────────────────────────────────────┘
```

### File Structure

```
/usr/local/etc/tpm2/
├── root.key          # Plaintext keyfile (32 bytes)
├── home.key          # Plaintext keyfile (32 bytes)
├── root.pub          # TPM2 public key
├── root.priv         # TPM2 private key (sealed)
├── home.pub          # TPM2 public key
├── home.priv         # TPM2 private key (sealed)
├── primary.ctx       # Primary storage key context
└── pcr.policy        # PCR policy (sha256:0,2,7)

/usr/local/libexec/
└── tpm2-unseal       # Main unlock script

/usr/lib/dracut/modules.d/95tpm2-keyfile/
├── module-setup.sh   # Dracut module definition
├── parse-tpm2.sh     # Command-line parser
└── tpm2-unlock.sh    # Hook script

/etc/
├── crypttab                    # LUKS device mapping
└── dracut.conf.d/
    └── 10-crypt.conf          # Dracut configuration
```

---

## Prerequisites

### Required Packages

```bash
# Install TPM2 tools and dependencies
sudo xbps-install -S tpm2-tools cryptsetup dracut
```

### Verify TPM2

```bash
# Check TPM device
ls -l /dev/tpm*

# Read PCR values
sudo tpm2_pcrread sha256:0,2,7
```

### LUKS Setup

System must have LUKS-encrypted partitions:

```bash
# Example configuration
/dev/nvme0n1p2  → root (LUKS)
/dev/nvme0n1p3  → home (LUKS)
```

---

## Implementation

### Step 1: Setup Script

Create the main setup script that:
- Generates random keyfiles
- Seals them with TPM2
- Adds keyfiles to LUKS slots
- Creates dracut module
- Configures system files

**Script**: `scripts/setup-tpm2-keyfile.sh`

Key operations:
1. Generate 32-byte random keyfiles
2. Create TPM2 policy for PCR 0,2,7
3. Seal keyfiles with TPM2
4. Add keyfiles to LUKS slots
5. Create dracut module
6. Configure crypttab and dracut.conf

### Step 2: Main Unlock Script

**File**: `/usr/local/libexec/tpm2-unseal`

This script runs in initramfs and performs the unlock:

```bash
#!/bin/sh
# TPM2 unseal script for initramfs

TPM2_DIR="/usr/local/etc/tpm2"
PCR_SELECTION="sha256:0,2,7"

unseal_and_unlock() {
    local name="$1"
    local uuid="$2"
    local keyfile="/tmp/tpm2-${name}.key"
    
    # 1. Create primary key (storage key)
    tpm2_createprimary -C o -g sha256 -G rsa -c /tmp/primary.ctx
    
    # 2. Load sealed object from .pub/.priv
    tpm2_load -C /tmp/primary.ctx \
        -u "${TPM2_DIR}/${name}.pub" \
        -r "${TPM2_DIR}/${name}.priv" \
        -c "/tmp/${name}.ctx"
    
    # 3. Unseal keyfile with PCR policy
    tpm2_unseal -c "/tmp/${name}.ctx" \
        -p pcr:$PCR_SELECTION > "$keyfile"
    
    # 4. Unlock LUKS device
    cryptsetup open --type luks \
        --key-file "$keyfile" \
        "/dev/disk/by-uuid/$uuid" \
        "$name"
    
    rm -f "$keyfile"
}

# Main execution
unseal_and_unlock "root" "UUID-HERE"
unseal_and_unlock "home" "UUID-HERE"
```

**Key Points**:
- TPM2 contexts (`.ctx` files) are **not portable** between sessions
- Must reconstruct from `.pub`/`.priv` each time
- PCR policy ensures unlock only with correct system state

### Step 3: Dracut Module

**Directory**: `/usr/lib/dracut/modules.d/95tpm2-keyfile/`

#### module-setup.sh

Defines the dracut module:

```bash
#!/bin/bash

check() {
    require_binaries tpm2_unseal cryptsetup || return 1
    return 0
}

depends() {
    echo crypt
    return 0
}

install() {
    # Install hook at initqueue/settled
    inst_hook initqueue/settled 60 "$moddir/tpm2-unlock.sh"
    
    # Install TPM2 tools
    inst_multiple tpm2_unseal tpm2_load tpm2_createprimary
    inst_multiple tpm2_pcrread tpm2_flushcontext
    inst_multiple cryptsetup
    
    # Install unlock script
    inst_simple /usr/local/libexec/tpm2-unseal
    
    # Install TPM2 sealed objects
    inst_simple /usr/local/etc/tpm2/root.pub
    inst_simple /usr/local/etc/tpm2/root.priv
    inst_simple /usr/local/etc/tpm2/home.pub
    inst_simple /usr/local/etc/tpm2/home.priv
    inst_simple /usr/local/etc/tpm2/primary.ctx
    inst_simple /usr/local/etc/tpm2/pcr.policy
    
    # Install TPM2 libraries
    inst_libdir_file "libtss2-*.so*" "libtss2-tcti-*.so*"
}

installkernel() {
    instmods tpm_tis tpm_crb tpm
}
```

#### tpm2-unlock.sh

Hook script executed during boot:

```bash
#!/bin/sh
# Hook: initqueue/settled

command -v getarg >/dev/null 2>&1 || . /lib/dracut-lib.sh

info "TPM2: Hook initqueue/settled executed"

# Verify TPM device available
if [ -c /dev/tpm0 ] || [ -c /dev/tpmrm0 ]; then
    info "TPM2: TPM device found"
else
    warn "TPM2: TPM device not available"
    return 0
fi

# Wait for block devices
udevadm settle --timeout=5 2>/dev/null || sleep 2

# Execute unlock script
info "TPM2: Executing /usr/local/libexec/tpm2-unseal"
if /usr/local/libexec/tpm2-unseal 2>&1 | while read line; do 
    info "$line"
done; then
    info "TPM2: Unlock completed"
else
    warn "TPM2: Unlock failed, password required"
fi
```

### Step 4: System Configuration

#### /etc/crypttab

```
# crypttab: encrypted partitions
# TPM2 automatic unlock in initramfs

root UUID=<UUID_ROOT_PARTITION> none luks,discard
home UUID=<UUID_HOME_PARTITION> none luks,discard
```

**Important**: No keyfile specified (third field is `none`). The unlock happens in initramfs hook.

#### /etc/dracut.conf.d/10-crypt.conf

```bash
# LUKS configuration with TPM2 keyfile for Void Linux/runit
add_drivers+=" dm_crypt tpm tpm_tis tpm_crb "
add_dracutmodules+=" crypt tpm2-keyfile "

# Kernel parameters for LUKS
kernel_cmdline+=" rd.luks=1 "
kernel_cmdline+=" rd.luks.uuid=<UUID_ROOT_PARTITION> "
kernel_cmdline+=" rd.luks.uuid=<UUID_HOME_PARTITION> "

# Debug (uncomment if needed)
#kernel_cmdline+=" rd.debug rd.shell "
```

### Step 5: Generate Initramfs

```bash
# Regenerate for current kernel
sudo dracut --force --hostonly

# Or for specific kernel
sudo dracut --force --hostonly --kver 6.18.7_1
```

---

## Scripts Created

### 1. setup-tpm2-keyfile.sh

**Purpose**: Complete setup automation

**Location**: `scripts/setup-tpm2-keyfile.sh`

**What it does**:
1. Verifies TPM2 availability
2. Creates `/usr/local/etc/tpm2/` directory
3. Generates random keyfiles (32 bytes each)
4. Creates TPM2 PCR policy
5. Creates TPM2 primary object
6. Seals keyfiles with TPM2
7. Tests unseal operation
8. Adds keyfiles to LUKS slots (requires password)
9. Creates unlock script
10. Creates dracut module
11. Configures system files

**Usage**:
```bash
sudo bash setup-tpm2-keyfile.sh
```

**Prompts for**:
- LUKS password for root partition
- LUKS password for home partition

### 2. tpm2-unseal

**Purpose**: Unlock LUKS devices in initramfs

**Location**: `/usr/local/libexec/tpm2-unseal`

**Execution context**: initramfs (early boot)

**Process**:
```
1. Verify TPM device exists
2. For each device (root, home):
   a. Create TPM2 primary key
   b. Load sealed object from .pub/.priv
   c. Unseal keyfile using PCR policy
   d. Verify keyfile is not empty
   e. Use keyfile to unlock LUKS device
   f. Clean up temporary files
3. Exit with status code
```

**Exit codes**:
- `0`: All devices unlocked successfully
- `1`: Root device unlock failed (critical)

### 3. Dracut Module (95tpm2-keyfile)

**Purpose**: Integrate TPM2 unlock into dracut initramfs

**Location**: `/usr/lib/dracut/modules.d/95tpm2-keyfile/`

**Components**:

- **module-setup.sh**: Module definition
  - Checks for required binaries
  - Declares dependencies (crypt module)
  - Installs files into initramfs
  - Installs kernel modules

- **parse-tpm2.sh**: Command-line parsing (minimal)
  - Logs module loading

- **tpm2-unlock.sh**: Main hook
  - Executes at `initqueue/settled`
  - Verifies TPM availability
  - Calls tpm2-unseal script
  - Logs results

---

## Boot Process

### Timeline

```
[0s] GRUB loads kernel + initramfs
      ↓
[1s] Kernel initializes
      ↓
[2s] Initramfs unpacks
      ↓
[3s] udev triggers device detection
      ↓
[4s] Block devices appear in /dev
      ↓
[5s] initqueue/settled hook fires  ← TPM2 unlock happens HERE
      ↓
      ┌─────────────────────────────┐
      │ TPM2-UNSEAL Script          │
      │ 1. Verify TPM device        │
      │ 2. Create primary key       │
      │ 3. Load sealed objects      │
      │ 4. Unseal keyfiles         │
      │ 5. Unlock LUKS devices     │
      └─────────────┬───────────────┘
                    ↓
[8s] /dev/mapper/root available
[8s] /dev/mapper/home available
      ↓
[9s] Mount root filesystem
      ↓
[10s] switch_root to real system
      ↓
[11s] runit stage 1 (system initialization)
      ↓
[15s] Login prompt
```

### Hook Execution Order

```
cmdline (20-parse-tpm2.sh)
  ↓
pre-udev
  ↓
pre-trigger
  ↓
initqueue/settled (60-tpm2-unlock.sh)  ← Our hook
  ↓
initqueue/timeout
  ↓
pre-mount
  ↓
mount
```

**Critical**: `initqueue/settled` runs AFTER devices are ready but BEFORE cryptsetup prompts for password.

---

## Testing & Verification

### Pre-Boot Verification

```bash
# Verify TPM2 tools
sudo tpm2_pcrread sha256:0,2,7

# Verify keyfiles exist
sudo ls -l /usr/local/etc/tpm2/

# Test manual unseal
sudo tpm2_createprimary -C o -g sha256 -G rsa -c /tmp/test.ctx
sudo tpm2_load -C /tmp/test.ctx \
    -u /usr/local/etc/tpm2/root.pub \
    -r /usr/local/etc/tpm2/root.priv \
    -c /tmp/root.ctx
sudo tpm2_unseal -c /tmp/root.ctx -p pcr:sha256:0,2,7

# Verify initramfs contents
sudo lsinitrd /boot/initramfs-$(uname -r).img | grep tpm2
sudo lsinitrd /boot/initramfs-$(uname -r).img -f usr/local/libexec/tpm2-unseal

# Check LUKS slots
sudo cryptsetup luksDump /dev/nvme0n1p2 | grep "Key Slot"
```

### Boot Test

```bash
# Reboot and observe
sudo reboot
```

**Expected boot messages**:
```
TPM2: Hook initqueue/settled executed
TPM2: TPM device found
TPM2: Waiting for devices...
TPM2: Executing /usr/local/libexec/tpm2-unseal
TPM2-UNSEAL: === Starting LUKS unlock with TPM2 ===
TPM2-UNSEAL: TPM device available
TPM2-UNSEAL: Processing root (UUID=...)
TPM2-UNSEAL: Loading primary context
TPM2-UNSEAL: Loading object from pub/priv
TPM2-UNSEAL: Unsealing keyfile
TPM2-UNSEAL: Keyfile OK, unlocking /dev/...
TPM2-UNSEAL: root unlocked successfully
TPM2-UNSEAL: Processing home (UUID=...)
TPM2-UNSEAL: Loading primary context
TPM2-UNSEAL: Loading object from pub/priv
TPM2-UNSEAL: Unsealing keyfile
TPM2-UNSEAL: Keyfile OK, unlocking /dev/...
TPM2-UNSEAL: home unlocked successfully
TPM2-UNSEAL: === TPM2 unlock completed ===
TPM2: Unlock completed
```

**No password prompt = SUCCESS!**

### Post-Boot Verification

```bash
# Check devices are unlocked
lsblk -f

# Check boot logs
dmesg | grep -i tpm2
cat /var/log/messages | grep TPM2-UNSEAL

# Verify PCR values haven't changed
sudo tpm2_pcrread sha256:0,2,7
```

---

## Troubleshooting

### Problem: tpm2_unseal fails

**Symptoms**:
```
TPM2-UNSEAL ERROR: tpm2_unseal failed
Enter passphrase for /dev/nvme0n1p2:
```

**Causes**:
1. PCR values changed (firmware/bootloader update)
2. TPM device not accessible
3. Sealed object corrupted

**Solutions**:

```bash
# Check current PCR values
sudo tpm2_pcrread sha256:0,2,7

# Test unseal manually
sudo tpm2_createprimary -C o -g sha256 -G rsa -c /tmp/test.ctx
sudo tpm2_load -C /tmp/test.ctx \
    -u /usr/local/etc/tpm2/root.pub \
    -r /usr/local/etc/tpm2/root.priv \
    -c /tmp/root.ctx
sudo tpm2_unseal -c /tmp/root.ctx -p pcr:sha256:0,2,7

# If fails, regenerate keyfiles
sudo bash scripts/setup-tpm2-keyfile.sh
sudo dracut --force
```

### Problem: Devices not found

**Symptoms**:
```
TPM2-UNSEAL ERROR: Device /dev/disk/by-uuid/... not found
```

**Causes**:
1. Hook executing too early
2. Device UUIDs incorrect
3. Kernel drivers not loaded

**Solutions**:

```bash
# Increase wait time
# Edit /usr/local/libexec/tpm2-unseal
# Change: sleep 2  →  sleep 5

# Verify UUIDs match
sudo blkid | grep crypto_LUKS
cat /usr/local/libexec/tpm2-unseal | grep UUID

# Check kernel modules
lsinitrd /boot/initramfs-$(uname -r).img | grep dm_crypt
```

### Problem: TPM device not found

**Symptoms**:
```
TPM2-UNSEAL ERROR: TPM device not found
```

**Causes**:
1. TPM disabled in BIOS
2. TPM driver not in initramfs
3. TPM ownership issue

**Solutions**:

```bash
# Enable in BIOS
# BIOS → Security → TPM Device: Enabled

# Verify driver loaded
lsmod | grep tpm

# Check device exists
ls -l /dev/tpm*

# Verify driver in initramfs
lsinitrd /boot/initramfs-$(uname -r).img | grep tpm_tis
```

### Debug Mode

Enable verbose dracut logging:

```bash
# Edit /etc/dracut.conf.d/10-crypt.conf
kernel_cmdline+=" rd.debug rd.shell "

# Regenerate
sudo dracut --force

# Reboot
# At emergency shell:
ls -l /dev/tpm*
tpm2_pcrread sha256:0,2,7
/usr/local/libexec/tpm2-unseal
```

---

## Maintenance

### Firmware/Bootloader Updates

When updating firmware or bootloader, PCR values change:

```bash
# After update, boot will require password
# Once logged in, regenerate keyfiles:

sudo bash scripts/setup-tpm2-keyfile.sh
sudo dracut --force
sudo reboot
```

### Kernel Updates

Void Linux auto-generates initramfs on kernel install, but verify:

```bash
# After kernel update
sudo dracut --force --hostonly --kver <NEW_KERNEL_VERSION>

# Example
sudo dracut --force --hostonly --kver 6.18.9_1
```

### Remove TPM2 Auto-Unlock

To return to password-only:

```bash
# Remove LUKS keyfile slots
sudo cryptsetup luksKillSlot /dev/nvme0n1p2 2
sudo cryptsetup luksKillSlot /dev/nvme0n1p3 2

# Remove TPM2 files
sudo rm -rf /usr/local/etc/tpm2/
sudo rm /usr/local/libexec/tpm2-unseal

# Remove dracut module
sudo rm -rf /usr/lib/dracut/modules.d/95tpm2-keyfile/

# Restore simple dracut config
sudo cat > /etc/dracut.conf.d/10-crypt.conf << 'EOF'
add_drivers+=" dm_crypt "
add_dracutmodules+=" crypt "
kernel_cmdline+=" rd.luks=1 "
kernel_cmdline+=" rd.luks.uuid=<UUID_ROOT_PARTITION> "
kernel_cmdline+=" rd.luks.uuid=<UUID_HOME_PARTITION> "
EOF

# Update crypttab
sudo cat > /etc/crypttab << 'EOF'
root UUID=<UUID_ROOT_PARTITION> none luks,discard
home UUID=<UUID_HOME_PARTITION> none luks,discard
EOF

# Regenerate initramfs
sudo dracut --force
```

### Backup LUKS Headers

**CRITICAL**: Always backup LUKS headers:

```bash
# Backup
sudo cryptsetup luksHeaderBackup /dev/nvme0n1p2 \
    --header-backup-file /root/luks-header-root.img

sudo cryptsetup luksHeaderBackup /dev/nvme0n1p3 \
    --header-backup-file /root/luks-header-home.img

# Store backups securely (external drive, USB, etc.)
```

---

## Security Considerations

### PCR Policy

Keyfiles are sealed with PCR 0, 2, 7:

- **PCR 0**: Core System Firmware Executable Code
  - Changes on: Firmware update, BIOS settings change
  
- **PCR 2**: Extended or Pluggable Executable Code
  - Changes on: Bootloader update, boot config change
  
- **PCR 7**: Secure Boot State
  - Changes on: Secure Boot enable/disable, key changes

**Result**: System auto-unlocks ONLY if firmware, bootloader, and secure boot state are unchanged.

### Keyfile Storage

**Plaintext keyfiles** exist on disk:
- Location: `/usr/local/etc/tpm2/root.key`, `home.key`
- Permissions: 600 (root only)
- Risk: If attacker has root access, they can read keyfiles

**Mitigation**:
- Root filesystem is LUKS-encrypted (keyfiles inaccessible when system off)
- Physical security of machine
- Consider deleting plaintext keyfiles after testing

```bash
# Optional: Delete plaintext keyfiles (keep sealed objects)
sudo rm /usr/local/etc/tpm2/root.key
sudo rm /usr/local/etc/tpm2/home.key

# Note: Cannot test unseal manually without them
# But sealed .pub/.priv files are sufficient for boot
```

### TPM Ownership

- TPM must be accessible to OS
- No TPM ownership password set (or provide to tpm2-tools)
- Physical presence may be required for TPM operations

### Evil Maid Attacks

**TPM2 protects against**:
- Software-based boot attacks (modified bootloader won't unseal)
- Remote attacks (attacker needs physical access to change firmware)

**TPM2 does NOT protect against**:
- Physical firmware flashing (attacker with physical access)
- TPM chip replacement
- Cold boot attacks (RAM extraction)
- Hardware keyloggers

**Enhanced security**:
- Add PCR 4 (Boot Manager) to policy
- Add PCR 5 (GPT/Partition Table) to policy
- Enable Secure Boot
- Use UEFI password
- Physical security of machine

### LUKS Slots

Current configuration:
- **Slot 0**: Original password (keep this!)
- **Slot 1**: Old Clevis binding (can be removed)
- **Slot 2**: TPM2 keyfile (active)

**Best practice**: Always keep at least one password slot for recovery.

```bash
# Remove old Clevis binding (optional)
sudo cryptsetup luksKillSlot /dev/nvme0n1p2 1
sudo cryptsetup luksKillSlot /dev/nvme0n1p3 1
```

---

## Comparison: Clevis vs Custom Implementation

| Aspect | Clevis | Custom TPM2 Keyfile |
|--------|--------|-------------------|
| **Compatibility** | systemd only | Works with runit |
| **Complexity** | High (many dependencies) | Medium (direct TPM2 tools) |
| **Dependencies** | Jose, curl, luksmeta, Clevis | tpm2-tools, cryptsetup |
| **Hook mechanism** | `initqueue/online` | `initqueue/settled` |
| **Initramfs size** | Larger (~100MB) | Smaller (~63MB) |
| **Network dependency** | Expected | None |
| **Maintenance** | Package manager | Manual scripts |
| **Debugging** | Difficult (complex stack) | Easier (simple scripts) |
| **Documentation** | Limited for runit | This document |
| **Production ready** | Yes (systemd) | Yes (runit) |

---

## Appendix A: File Listing

### Scripts

```
scripts
├── setup-tpm2-keyfile.sh              # Main setup 
```

### System Files

```
/usr/local/etc/tpm2/
├── root.key         # 32 bytes, 600 permissions
├── home.key         # 32 bytes, 600 permissions
├── root.pub         # 80 bytes, 660 permissions
├── root.priv        # 160 bytes, 660 permissions
├── home.pub         # 80 bytes, 660 permissions
├── home.priv        # 160 bytes, 660 permissions
├── primary.ctx      # 1916 bytes, 660 permissions
└── pcr.policy       # 32 bytes, 660 permissions

/usr/local/libexec/
└── tpm2-unseal      # 2.3 KB, 755 permissions

/usr/lib/dracut/modules.d/95tpm2-keyfile/
├── module-setup.sh  # 988 bytes, 755 permissions
├── parse-tpm2.sh    # 126 bytes, 755 permissions
└── tpm2-unlock.sh   # 517 bytes, 755 permissions

/etc/
├── crypttab                           # 203 bytes
└── dracut.conf.d/10-crypt.conf       # 445 bytes

/boot/
├── initramfs-6.18.7_1.img            # 63 MB
└── initramfs-6.18.8_1.img            # 63 MB
```

---

## Appendix B: Complete Script Listings

### setup-tpm2-keyfile.sh

See separate file: `scripts/setup-tpm2-keyfile.sh`

Total lines: ~350
Functions:
- Main setup flow
- Error handling
- User prompts
- File creation
- TPM2 operations

### tpm2-unseal

See: `/usr/local/libexec/tpm2-unseal`

Total lines: ~80
Functions:
- `log_info()`: Logging to stderr
- `log_error()`: Error logging
- `unseal_and_unlock()`: Main unlock logic
- Main execution flow

---

## Appendix C: Troubleshooting Quick Reference

| Symptom | Likely Cause | Solution |
|---------|-------------|----------|
| Password prompt at boot | TPM2 unseal failed | Check PCR values, regenerate keyfiles |
| "TPM device not found" | TPM disabled/driver missing | Enable in BIOS, check kernel modules |
| "Device not found" | Hook too early | Increase sleep time in script |
| "Keyfile empty" | Unseal returned no data | Check PCR policy, test manual unseal |
| "cryptsetup open failed" | Wrong keyfile | Verify LUKS slot, test manual unlock |
| System hangs | Wrong hook timing | Verify hook is in initqueue/settled |
| No TPM2 messages | Module not loaded | Check dracut config, regenerate initramfs |

---

## Conclusion

This implementation provides a **production-ready** TPM2 automatic unlock solution for Void Linux with runit, without relying on Clevis. The custom dracut module approach gives full control over the boot process and works reliably with non-systemd init systems.

### Key Achievements

✅ Automatic LUKS unlock with TPM2  
✅ Compatible with Void Linux + runit  
✅ Secure PCR-based attestation  
✅ Clean fallback to password  
✅ Comprehensive documentation  
✅ Maintainable custom scripts  

### Support & Contribution

This solution was developed specifically for Void Linux with runit. It may be adapted for other non-systemd distributions with similar requirements.

**Author**: Antonio Salsi <passy.linux@zresa.it>  
**Date**: February 2, 2026  
**Version**: 3.0 (Final)  
**License**: GPL-3  

---

**End of Documentation**

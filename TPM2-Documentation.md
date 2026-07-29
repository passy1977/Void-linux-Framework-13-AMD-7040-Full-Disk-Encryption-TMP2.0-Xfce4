# TPM2 Automatic LUKS Unlock for Void Linux with runit

**Complete Technical Documentation**

---

## Table of Contents

1. [Overview](#overview)
2. [Problem Statement](#problem-statement)
3. [Solution Architecture](#solution-architecture)
4. [Prerequisites](#prerequisites)
5. [Quick Start / Installation](#quick-start--installation)
6. [Implementation](#implementation)
7. [Scripts Created](#scripts-created)
8. [Boot Process](#boot-process)
9. [Testing & Verification](#testing--verification)
10. [Troubleshooting](#troubleshooting)
11. [Maintenance](#maintenance)
12. [Security Considerations](#security-considerations)

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
- **Boot Manager**: GRUB
- **Encryption**: LUKS2 (root), LUKS2 (home)

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
│ GRUB → Kernel → Initramfs                               │
│                     ↓                                   │
│         udev triggers device detection                  │
│                     ↓                                   │
│         initqueue/settled/60-tpm2-unlock.sh             │
│                     ↓                                   │
│         /usr/local/libexec/tpm2-unseal                  │
│                     ↓                                   │
│    ┌────────────────┴────────────────┐                  │
│    │  For each LUKS device:          │                  │
│    │  1. Load TPM2 primary key       │                  │
│    │  2. Load sealed object          │                  │
│    │  3. Unseal keyfile with PCR     │                  │
│    │  4. Unlock with cryptsetup      │                  │
│    └────────────────┬────────────────┘                  │
│                     ↓                                   │
│         Root filesystem mounted                         │
│                     ↓                                   │
│         switch_root → runit stage 1                     │
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

## Quick Start / Installation

This is the practical "how do I actually use this" walkthrough. For what
each step does internally, see [Implementation](#implementation).

### 1. Copy the script

`scripts/setup-tpm2-keyfile.sh` in this repo is a **template** (placeholder
UUIDs, safe to keep in version control). Install your own copy outside the
repo, e.g. in `/usr/local/bin/`:

```bash
sudo cp scripts/setup-tpm2-keyfile.sh /usr/local/bin/setup-tpm2-keyfile.sh
sudo chmod 700 /usr/local/bin/setup-tpm2-keyfile.sh
```

`700` rather than `755`: once you fill in your real UUIDs the script is
host-specific and should not be world-readable.

### 2. Find your partition UUIDs

```bash
sudo blkid | grep crypto_LUKS
```

Match each `crypto_LUKS` line to its mountpoint (root `/`, home `/home`),
e.g.:

```
/dev/nvme0n1p2: UUID="215b0812-6b31-4886-88b4-1b61fbe4d9ca" TYPE="crypto_LUKS"
/dev/nvme0n1p3: UUID="2af3f04d-2968-4185-85d7-a3448a9b7afb" TYPE="crypto_LUKS"
```

### 3. Edit the copy with your real values

Open `/usr/local/bin/setup-tpm2-keyfile.sh` and edit the four variables near
the top of the file:

```bash
ROOT_UUID="215b0812-6b31-4886-88b4-1b61fbe4d9ca"   # was xxxxxxxx-xxxx-...
HOME_UUID="2af3f04d-2968-4185-85d7-a3448a9b7afb"   # was yyyyyyyy-yyyy-...
ROOT_DEV="/dev/nvme0n1p2"
HOME_DEV="/dev/nvme0n1p3"
```

- `ROOT_UUID`/`HOME_UUID` must be the **LUKS container's** UUID (the
  `crypto_LUKS` UUID from `blkid` on the raw partition), not the filesystem
  UUID inside the unlocked `/dev/mapper/...` device.
- `ROOT_DEV`/`HOME_DEV` are the raw block devices, used only to read the
  *existing* password when adding the TPM keyslot (script step `[7/9]`) —
  not `/dev/mapper/root` or `/dev/mapper/home`.
- If your keyslot layout needs a different reserved slot than the default,
  also edit `TPM_KEY_SLOT` — see [LUKS Slots](#luks-slots).

The script refuses to run (exit 1) if `ROOT_UUID`/`HOME_UUID` are still the
template placeholders, so this step cannot be silently skipped.

### 4. Run it

```bash
sudo /usr/local/bin/setup-tpm2-keyfile.sh
```

You'll be prompted for the **existing** LUKS password of root and home —
this only authorizes adding the new TPM-sealed key into `TPM_KEY_SLOT`
(default slot `1`); your original password in slot `0` is left untouched.

### 5. Regenerate the initramfs and reboot

The script edits files on disk but does **not** rebuild the initramfs
itself — skipping this step means the running system keeps booting with
whatever was baked in before:

```bash
sudo dracut --force --hostonly
sudo reboot
```

On reboot you should see the [expected boot messages](#boot-test) with no
password prompt.

### Re-running later (BIOS/firmware updates, TPM reset, etc.)

The script is safe to re-run whenever you need to reseal — e.g. after a
BIOS update resets the TPM (see the [case study](#problem-bios-update-invalidates-tpm-unlock-case-study)).
It's idempotent: `TPM_KEY_SLOT` is killed and recreated rather than
accumulating new slots, and `/etc/crypttab` is updated without disturbing
unrelated entries. Just repeat steps 4-5 — no need to re-copy the script or
re-edit the UUIDs unless the partitions themselves changed.

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
- The primary key is recreated with `tpm2_createprimary` on **every boot**
  instead of shipping a pre-saved `primary.ctx` context blob in the initramfs.
  A TPM 2.0 primary derived from a fixed hierarchy/template (no unique data)
  is deterministic — same seed + same template ⇒ same key — so recreating it
  is free and, critically, **immune to TPM resets** (e.g. a BIOS/firmware
  update that resets the TPM's reset/restart counter). A saved context blob,
  by contrast, is tied to that counter and becomes invalid after such a
  reset — this was the actual root cause of a full lockout after a BIOS
  update (see [Troubleshooting: BIOS update invalidates TPM unlock](#problem-bios-update-invalidates-tpm-unlock-case-study)).

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
info "TPM2: Waiting for devices..."
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
# TPM2 keyfile automatic unlock in initramfs

# root/home are unlocked by the tpm2-keyfile dracut hook
# (/usr/local/libexec/tpm2-unseal), not by this file. Kept commented
# out for reference only; do not uncomment.
#root UUID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx none luks,discard
#home UUID=yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy none luks,discard
```

**Important**: root/home are kept **commented out** here on purpose. The
`crypt` dracut module (a dependency of our `tpm2-keyfile` module) parses
`/etc/crypttab` on its own and, if these entries were active, would try to
prompt for a password for them independently of — and possibly before —
our `initqueue/settled` hook, which can produce a spurious/duplicate
password prompt even when the TPM path is fine. Leaving them commented
means only our custom hook ever touches these two devices; the standard
`crypt` module still provides the manual-password fallback via the
`rd.luks.uuid=` kernel parameters below, independent of crypttab.

The setup script only ever touches its own two commented lines (matched by
UUID) and never overwrites the rest of the file, so any unrelated
crypttab entries you already have (e.g. a separate encrypted backup
volume) are preserved across re-runs.

#### /etc/dracut.conf.d/10-crypt.conf

```bash
# LUKS configuration with TPM2 keyfile for Void Linux/runit
add_drivers+=" dm_crypt tpm tpm_tis tpm_crb "
add_dracutmodules+=" crypt tpm2-keyfile "

# Kernel parameters for LUKS
kernel_cmdline+=" rd.luks=1 "
kernel_cmdline+=" rd.luks.uuid=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx "
kernel_cmdline+=" rd.luks.uuid=yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy "

# Debug (uncomment if needed)
#kernel_cmdline+=" rd.debug rd.shell "
#kernel_cmdline+=" rd.luks.allow-discards "
```

Note: `--allow-discards` is passed directly to `cryptsetup open` inside
`tpm2-unseal` for the TPM-unlocked path, so TRIM works there regardless of
this kernel parameter. `rd.luks.allow-discards` only affects the manual
password fallback handled by the standard `crypt` module; it is left
disabled here as a deliberate, minor security trade-off (discards can leak
which blocks are in use to an attacker with physical access) — enable it
if you prefer TRIM support on the fallback path too.

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
1. Refuses to run if `ROOT_UUID`/`HOME_UUID` are still the template's
   placeholder values (`xxxxxxxx-...`/`yyyyyyyy-...`), pointing at `blkid`
2. Verifies TPM2 availability
3. Creates `/usr/local/etc/tpm2/` directory
4. Generates random keyfiles (32 bytes each)
5. Creates TPM2 PCR policy
6. Creates TPM2 primary object
7. Seals keyfiles with TPM2
8. Tests unseal operation
9. Adds keyfiles to LUKS slots (requires password)
10. Creates unlock script
11. Creates dracut module
12. Configures system files

**Usage**:
```bash
sudo bash setup-tpm2-keyfile.sh
```

**Prompts for**:
- LUKS password for root partition
- LUKS password for home partition

**Fixed LUKS keyslot** (`TPM_KEY_SLOT`, default `1`): the script always
writes the TPM-sealed key to this same keyslot, killing whatever was
previously in it first (`cryptsetup luksKillSlot`, ignored if empty) before
adding the new key with `cryptsetup luksAddKey --key-slot`. Without this,
every re-run (e.g. after a firmware update forces a reseal) would consume a
new keyslot instead of replacing the old one. Slot 0 is assumed to hold the
normal password and must not collide with `TPM_KEY_SLOT`.

`cryptsetup` prints `WARNING: The --key-slot parameter is used for new
keyslot number.` on this operation — this is expected (it is cryptsetup
confirming `--key-slot` targets the *new* key, exactly the intended usage
per its own man page example) and is filtered out of the script's output.

**Non-destructive `/etc/crypttab` update**: the script never truncates the
file. It only removes lines matching `$ROOT_UUID`/`$HOME_UUID` and the
explanatory comment block from a previous run of this script (idempotent),
then appends a fresh copy of both, leaving any other entries (e.g. an
unrelated encrypted volume) untouched. Earlier versions only de-duplicated
the UUID lines, not the 3-line explanatory comment above them, so re-running
the script repeatedly duplicated that comment block — fixed by removing all
five lines (comment block + both UUID lines) before re-appending them as a
unit.

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
  - Generated for structural consistency but **not wired into any hook** —
    `module-setup.sh` never calls `inst_hook` for it, so it is currently
    dead code kept for possible future use (e.g. a `tpm2.debug` cmdline
    flag)

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
      │ 4. Unseal keyfiles          │
      │ 5. Unlock LUKS devices      │
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

**Critical**: `initqueue/settled` runs AFTER devices are ready but BEFORE cryptsetup prompts for password. A previous revision of this module used `inst_hook cmdline 20 parse-tpm2.sh` + `inst_hook pre-mount 50 tpm2-unlock.sh` instead — `pre-mount` fires too late (after the standard `crypt` module has already started asking for a password in the `initqueue` phase), which reintroduced the manual-password prompt even with everything else configured correctly. See [Troubleshooting: BIOS update invalidates TPM unlock](#problem-bios-update-invalidates-tpm-unlock-case-study).

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

### Problem: BIOS update invalidates TPM unlock (case study)

**Trigger**: a BIOS/firmware update reset the TPM. Afterwards the system
kept asking for the LUKS password, and the boot log showed the TPM unlock
being retried in a loop, even though the disks eventually did get mounted
once the password was entered.

Re-running `setup-tpm2-keyfile.sh` (to reseal against the new PCR 0 value)
did not fix it. Diagnosis, done by comparing the live system against a
known-good Timeshift snapshot taken before the incident, found **four
separate regressions**, all in the same generator script:

1. **Placeholder UUIDs never substituted.** The heredocs generating
   `/usr/local/libexec/tpm2-unseal`, `/etc/dracut.conf.d/10-crypt.conf` and
   `/etc/crypttab` used quoted delimiters (`<< 'UNSEAL_SCRIPT'`, etc.),
   which prevents bash from expanding `$ROOT_UUID`/`$HOME_UUID`. The
   generated files ended up with the literal placeholder text
   (`xxxxxxxx-xxxx-...`) instead of real UUIDs, so the TPM hook looked for
   a `/dev/disk/by-uuid/xxxxxxxx-...` device that never existed and failed
   immediately. **Fix**: substitute the UUIDs with `sed` after the heredoc
   for the script that has its own runtime variables to protect
   (`tpm2-unseal`), and simply drop the quotes on heredocs with no such
   conflict (`dracut.conf.d`, `crypttab`).
2. **Wrong dracut hook point.** The module had drifted to
   `inst_hook cmdline 20 parse-tpm2.sh` + `inst_hook pre-mount 50
   tpm2-unlock.sh`. `pre-mount` runs too late — by the time it fires, the
   standard `crypt` module has already been asking for a password during
   `initqueue`. **Fix**: restore `inst_hook initqueue/settled 60
   tpm2-unlock.sh`, which runs before that prompt.
3. **`primary.ctx` invalidated by the TPM reset.** The unseal script had
   drifted to loading a `primary.ctx` context blob pre-saved and shipped in
   the initramfs. TPM 2.0 context blobs are tied to the TPM's
   reset/restart counter; a BIOS update that resets the TPM invalidates any
   blob saved before it. **Fix**: recreate the primary with
   `tpm2_createprimary` on every boot instead (see [Step 2](#step-2-main-unlock-script)) —
   deterministic for a fixed template, so it needs no persisted state and
   survives TPM resets.
4. **Destructive `/etc/crypttab` regeneration.** The script fully
   overwrote `/etc/crypttab` on every run, silently deleting unrelated
   entries (e.g. a separate encrypted backup volume) that happened to
   already be in the file. **Fix**: make the crypttab update additive/
   idempotent (see [Step 4](#etccrypttab)).

**Lesson**: after any change to this generator script, diff its output
against a backup of a boot that is *known* to have worked (a filesystem
snapshot, a git history, etc.) rather than assuming the "obviously
correct" version is actually what was last proven on real hardware — three
of the four regressions above were introduced by well-intentioned but
untested edits.

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
sudo cryptsetup luksKillSlot /dev/nvme0n1p2 1
sudo cryptsetup luksKillSlot /dev/nvme0n1p3 1

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
kernel_cmdline+=" rd.luks.uuid=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx "
kernel_cmdline+=" rd.luks.uuid=yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy "
EOF

# Update crypttab
sudo cat > /etc/crypttab << 'EOF'
root UUID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx none luks,discard
home UUID=yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy none luks,discard
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
- **Slot `TPM_KEY_SLOT`** (default `1`): TPM2 keyfile — fixed and
  reserved. `setup-tpm2-keyfile.sh` always kills and recreates this exact
  slot on every run (see [Scripts Created](#1-setup-tpm2-keyfilesh)), so it
  never accumulates extra slots across re-runs (e.g. after a BIOS update
  forces a reseal).

**Best practice**: Always keep at least one password slot for recovery,
and make sure `TPM_KEY_SLOT` in the script never collides with it. If you
previously had a Clevis binding or another leftover slot occupying slot 1,
the script's `luksKillSlot` step removes it automatically before adding
the TPM key — check first with `cryptsetup luksDump` if you are not sure
what a given slot currently holds.

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

### Changelog

- **v3.2** (July 29, 2026): Added the [Quick Start / Installation](#quick-start--installation)
  walkthrough (copying the script to `/usr/local/bin`, finding and setting
  real partition UUIDs, running it, regenerating the initramfs). Fixed a
  bug where re-running the script repeatedly duplicated the explanatory
  comment block in `/etc/crypttab` (see [Scripts Created](#1-setup-tpm2-keyfilesh)).
- **v3.1** (July 27, 2026): Restored `initqueue/settled` hook timing,
  runtime primary regeneration, and non-destructive `/etc/crypttab`
  handling after a BIOS-update-triggered TPM reset exposed regressions
  introduced by an untested edit of the generator script. Added a fixed,
  reserved LUKS keyslot (`TPM_KEY_SLOT`) so re-running the setup script no
  longer accumulates keyslots, a startup guard against unfilled placeholder
  UUIDs, and fixed a heredoc-quoting bug that had left literal placeholder
  UUIDs in the generated `tpm2-unseal`/`dracut.conf.d`/`crypttab` files.
  See [Troubleshooting: BIOS update invalidates TPM unlock](#problem-bios-update-invalidates-tpm-unlock-case-study).
- **v3.0** (February 2, 2026): Initial final documentation.

**Author**: Antonio Salsi <passy.linux@zresa.it>  
**Date**: July 29, 2026 (last updated)  
**Version**: 3.2  
**License**: GPL-3  

---

**End of Documentation**

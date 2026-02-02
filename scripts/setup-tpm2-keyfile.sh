#!/bin/bash
set -e

# Script to configure LUKS unlock with TPM2-sealed keyfiles
# Void Linux with runit - Without Clevis

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Error: Run as root${NC}"
    exit 1
fi

echo -e "${GREEN}╔═══════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  Setup TPM2 Keyfile per LUKS - Void Linux + runit    ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════╝${NC}"
echo ""

# Configurazione
TPM2_DIR="/usr/local/etc/tpm2"
ROOT_UUID="<UUID_ROOT_PARTITION>"
HOME_UUID="<UUID_HOME_PARTITION>"
ROOT_DEV="/dev/nvme0n1p2"
HOME_DEV="/dev/nvme0n1p3"

# PCR come Clevis: 0=firmware, 2=bootloader, 7=secure boot
PCR_SELECTION="sha256:0,2,7"

echo -e "${YELLOW}[1/9] Verifying TPM2...${NC}"
if ! tpm2_pcrread $PCR_SELECTION >/dev/null 2>&1; then
    echo -e "${RED}Error: TPM2 not accessible${NC}"
    exit 1
fi
echo -e "${BLUE}✓ TPM2 available${NC}"

echo ""
echo -e "${YELLOW}[2/9] Creating directory ${TPM2_DIR}...${NC}"
mkdir -p "$TPM2_DIR"
chmod 700 "$TPM2_DIR"
echo -e "${BLUE}✓ Directory created${NC}"

echo ""
echo -e "${YELLOW}[3/9] Generating random keyfiles...${NC}"
# Separate keyfiles for root and home
dd if=/dev/urandom of="${TPM2_DIR}/root.key" bs=32 count=1 status=none
dd if=/dev/urandom of="${TPM2_DIR}/home.key" bs=32 count=1 status=none
chmod 600 "${TPM2_DIR}/root.key" "${TPM2_DIR}/home.key"
echo -e "${BLUE}✓ Keyfiles generated:${NC}"
echo "  - ${TPM2_DIR}/root.key (32 bytes)"
echo "  - ${TPM2_DIR}/home.key (32 bytes)"

echo ""
echo -e "${YELLOW}[4/9] Reading current PCR values...${NC}"
tpm2_pcrread $PCR_SELECTION | head -10

echo ""
echo -e "${YELLOW}[5/9] Sealing keyfiles with TPM2...${NC}"

# Create PCR policy
tpm2_createpolicy --policy-pcr -l $PCR_SELECTION -L "${TPM2_DIR}/pcr.policy"

# Create primary object (storage key)
tpm2_createprimary -C o -g sha256 -G rsa -c "${TPM2_DIR}/primary.ctx"

# Seal root.key
echo "Sealing root.key..."
tpm2_create -C "${TPM2_DIR}/primary.ctx" \
    -L "${TPM2_DIR}/pcr.policy" \
    -i "${TPM2_DIR}/root.key" \
    -u "${TPM2_DIR}/root.pub" \
    -r "${TPM2_DIR}/root.priv"

tpm2_load -C "${TPM2_DIR}/primary.ctx" \
    -u "${TPM2_DIR}/root.pub" \
    -r "${TPM2_DIR}/root.priv" \
    -c "${TPM2_DIR}/root.ctx"

# Seal home.key
echo "Sealing home.key..."
tpm2_create -C "${TPM2_DIR}/primary.ctx" \
    -L "${TPM2_DIR}/pcr.policy" \
    -i "${TPM2_DIR}/home.key" \
    -u "${TPM2_DIR}/home.pub" \
    -r "${TPM2_DIR}/home.priv"

tpm2_load -C "${TPM2_DIR}/primary.ctx" \
    -u "${TPM2_DIR}/home.pub" \
    -r "${TPM2_DIR}/home.priv" \
    -c "${TPM2_DIR}/home.ctx"

echo -e "${BLUE}✓ Keyfiles sealed with TPM2${NC}"

echo ""
echo -e "${YELLOW}[6/9] Testing unsealing...${NC}"
# Test unseal
tpm2_unseal -c "${TPM2_DIR}/root.ctx" -p pcr:$PCR_SELECTION > /tmp/test_root.key
if cmp -s "${TPM2_DIR}/root.key" /tmp/test_root.key; then
    echo -e "${GREEN}✓ Test root.key OK${NC}"
    rm /tmp/test_root.key
else
    echo -e "${RED}✗ Test root.key FAILED${NC}"
    exit 1
fi

tpm2_unseal -c "${TPM2_DIR}/home.ctx" -p pcr:$PCR_SELECTION > /tmp/test_home.key
if cmp -s "${TPM2_DIR}/home.key" /tmp/test_home.key; then
    echo -e "${GREEN}✓ Test home.key OK${NC}"
    rm /tmp/test_home.key
else
    echo -e "${RED}✗ Test home.key FAILED${NC}"
    exit 1
fi

echo ""
echo -e "${YELLOW}[7/9] Adding keyfiles as LUKS slots...${NC}"
echo ""
echo -e "${BLUE}Root partition ($ROOT_DEV):${NC}"
read -s -p "Enter existing LUKS password for root: " ROOT_PASS
echo ""
echo "$ROOT_PASS" | cryptsetup luksAddKey "$ROOT_DEV" "${TPM2_DIR}/root.key" -
echo -e "${GREEN}✓ Keyfile added to root${NC}"

echo ""
echo -e "${BLUE}Home partition ($HOME_DEV):${NC}"
read -s -p "Enter existing LUKS password for home: " HOME_PASS
echo ""
echo "$HOME_PASS" | cryptsetup luksAddKey "$HOME_DEV" "${TPM2_DIR}/home.key" -
echo -e "${GREEN}✓ Keyfile added to home${NC}"

echo ""
echo -e "${YELLOW}[8/9] Creating unseal script for initramfs...${NC}"

# Unseal script
mkdir -p /usr/local/libexec
cat > /usr/local/libexec/tpm2-unseal << 'UNSEAL_SCRIPT'
#!/bin/sh
# TPM2 unseal script for initramfs
# Unseals keyfiles and unlocks LUKS devices

TPM2_DIR="/usr/local/etc/tpm2"
PCR_SELECTION="sha256:0,2,7"

# Logger functions
log_info() {
    echo "TPM2-UNSEAL: $*" >&2
}

log_error() {
    echo "TPM2-UNSEAL ERROR: $*" >&2
}

# Unseals and unlocks a device
unseal_and_unlock() {
    local name="$1"
    local uuid="$2"
    local ctx_file="${TPM2_DIR}/${name}.ctx"
    
    log_info "Processing $name (UUID=$uuid)..."
    
    # Find device
    local device="/dev/disk/by-uuid/$uuid"
    if [ ! -b "$device" ]; then
        log_error "Device $device not found"
        return 1
    fi
    
    # Check if already open
    if [ -e "/dev/mapper/$name" ]; then
        log_info "$name already unlocked"
        return 0
    fi
    
    # Unseal keyfile
    log_info "Unsealing keyfile for $name..."
    if ! tpm2_unseal -c "$ctx_file" -p pcr:$PCR_SELECTION 2>/dev/null | \
         cryptsetup open --type luks "$device" "$name" 2>/dev/null; then
        log_error "Unable to unlock $name with TPM2"
        return 1
    fi
    
    log_info "$name unlocked successfully"
    return 0
}

# Main
log_info "Starting LUKS unlock with TPM2"

# Wait for devices
sleep 1

# Unlock root
if ! unseal_and_unlock "root" "<UUID_ROOT_PARTITION>"; then
    log_error "Fallback to manual password for root"
    exit 1
fi

# Unlock home
if ! unseal_and_unlock "home" "<UUID_HOME_PARTITION>"; then
    log_error "Fallback to manual password for home"
    # Don't exit, home might not be critical
fi

log_info "Unlock completed"
exit 0
UNSEAL_SCRIPT

chmod +x /usr/local/libexec/tpm2-unseal
echo -e "${BLUE}✓ Script created: /usr/local/libexec/tpm2-unseal${NC}"

echo ""
echo -e "${YELLOW}[9/9] Configuring dracut...${NC}"

# Create dracut module
DRACUT_MOD_DIR="/usr/lib/dracut/modules.d/95tpm2-keyfile"
mkdir -p "$DRACUT_MOD_DIR"

cat > "$DRACUT_MOD_DIR/module-setup.sh" << 'MODULE_SETUP'
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
    inst_hook cmdline 20 "$moddir/parse-tpm2.sh"
    inst_hook pre-mount 50 "$moddir/tpm2-unlock.sh"
    
    inst_multiple tpm2_unseal tpm2_load tpm2_createprimary tpm2_pcrread tpm2_flushcontext
    inst_multiple cryptsetup
    
    inst_simple /usr/local/libexec/tpm2-unseal /usr/local/libexec/tpm2-unseal
    
    # Sealed keyfiles and TPM contexts
    inst_simple /usr/local/etc/tpm2/root.ctx
    inst_simple /usr/local/etc/tpm2/home.ctx
    inst_simple /usr/local/etc/tpm2/root.pub
    inst_simple /usr/local/etc/tpm2/root.priv
    inst_simple /usr/local/etc/tpm2/home.pub
    inst_simple /usr/local/etc/tpm2/home.priv
    inst_simple /usr/local/etc/tpm2/primary.ctx
    inst_simple /usr/local/etc/tpm2/pcr.policy
    
    inst_libdir_file "libtss2-*.so*" "libtss2-tcti-*.so*"
}

installkernel() {
    instmods tpm_tis tpm_crb tpm
}
MODULE_SETUP

cat > "$DRACUT_MOD_DIR/parse-tpm2.sh" << 'PARSE_TPM2'
#!/bin/sh
# Set variables for TPM2
command -v getarg >/dev/null 2>&1 || . /lib/dracut-lib.sh
info "TPM2: Module loaded"
PARSE_TPM2

cat > "$DRACUT_MOD_DIR/tpm2-unlock.sh" << 'TPM2_UNLOCK'
#!/bin/sh
# Pre-mount hook for TPM2 unlock
command -v getarg >/dev/null 2>&1 || . /lib/dracut-lib.sh

info "TPM2: Executing LUKS unlock"

# Wait for devices
udevadm settle --timeout=10 2>/dev/null || sleep 2

# Execute unlock
if /usr/local/libexec/tpm2-unseal; then
    info "TPM2: Unlock succeeded"
else
    warn "TPM2: Unlock failed, manual password required"
fi
TPM2_UNLOCK

chmod +x "$DRACUT_MOD_DIR/module-setup.sh"
chmod +x "$DRACUT_MOD_DIR/parse-tpm2.sh"
chmod +x "$DRACUT_MOD_DIR/tpm2-unlock.sh"

echo -e "${BLUE}✓ Dracut module created: $DRACUT_MOD_DIR${NC}"

# Configure dracut.conf
cat > /etc/dracut.conf.d/10-crypt.conf << 'DRACUT_CONF'
# LUKS configuration with TPM2 keyfile for Void Linux/runit
add_drivers+=" dm_crypt tpm tpm_tis tpm_crb "
add_dracutmodules+=" crypt tpm2-keyfile "

# Kernel parameters
kernel_cmdline+=" rd.luks=1 "
kernel_cmdline+=" rd.luks.uuid=<UUID_ROOT_PARTITION> "
kernel_cmdline+=" rd.luks.uuid=<UUID_HOME_PARTITION> "

# Debug (uncomment if needed)
#kernel_cmdline+=" rd.debug rd.shell "
DRACUT_CONF

echo -e "${BLUE}✓ Dracut configured${NC}"

# Update crypttab
cat > /etc/crypttab << 'CRYPTTAB'
# crypttab: encrypted partitions
# TPM2 keyfile automatic unlock in initramfs

root UUID=<UUID_ROOT_PARTITION> none luks,discard
home UUID=<UUID_HOME_PARTITION> none luks,discard
CRYPTTAB

echo -e "${BLUE}✓ Crypttab updated${NC}"

echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║            Configuration completed!                   ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════╝${NC}"

echo ""
echo -e "${YELLOW}Files created:${NC}"
ls -lh "$TPM2_DIR"

echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Regenerate initramfs:"
echo "   dracut --force --hostonly"
echo ""
echo "2. Verify content:"
echo "   lsinitrd /boot/initramfs-\$(uname -r).img | grep tpm2"
echo ""
echo "3. Reboot:"
echo "   reboot"
echo ""
echo -e "${GREEN}The system should unlock automatically with TPM2${NC}"
echo -e "${YELLOW}If it fails, the LUKS password will be requested${NC}"

#!/usr/bin/env bash
# Homelab NixOS installer — partitions, formats, and installs from flake ISO
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
die()   { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

# ── Checks ──
[[ $EUID -eq 0 ]] || die "Run as root: sudo homelab-install"

echo ""
echo -e "${CYAN}╔══════════════════════════════════════╗${NC}"
echo -e "${CYAN}║     Homelab NixOS Installer          ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════╝${NC}"
echo ""

# ── Disk selection ──
info "Available disks:"
echo ""
lsblk -d -o NAME,SIZE,MODEL -n | grep -v "loop\|sr\|ram" | while read -r line; do
  echo "  /dev/$line"
done
echo ""

read -rp "Disk to install on (e.g. sda, nvme0n1): " DISK_NAME
DISK="/dev/${DISK_NAME}"

[[ -b "$DISK" ]] || die "Disk $DISK not found"

DISK_SIZE=$(lsblk -b -d -o SIZE -n "$DISK" | tr -d ' ')
DISK_SIZE_GB=$((DISK_SIZE / 1024 / 1024 / 1024))

echo ""
warn "This will ERASE ALL DATA on $DISK (${DISK_SIZE_GB}GB)"
read -rp "Type YES to continue: " CONFIRM
[[ "$CONFIRM" == "YES" ]] || die "Aborted"

# ── Detect partition suffix (nvme uses p1, sata uses 1) ──
if [[ "$DISK" == *nvme* ]] || [[ "$DISK" == *mmcblk* ]]; then
  PART="${DISK}p"
else
  PART="${DISK}"
fi

# ── Swap size (match RAM, cap at 16GB) ──
RAM_GB=$(awk '/MemTotal/ {printf "%d", $2/1024/1024}' /proc/meminfo)
SWAP_GB=$((RAM_GB > 16 ? 16 : RAM_GB))
SWAP_END="$((SWAP_GB + 1)).0GiB"

info "RAM: ${RAM_GB}GB → Swap: ${SWAP_GB}GB"
echo ""

# ── Partition ──
info "Partitioning $DISK..."
parted "$DISK" -- mklabel gpt
parted "$DISK" -- mkpart ESP fat32 1MiB 512MiB
parted "$DISK" -- set 1 esp on
parted "$DISK" -- mkpart swap linux-swap 512MiB "$SWAP_END"
parted "$DISK" -- mkpart primary "$SWAP_END" 100%
ok "Partitioned"

# ── Format ──
info "Formatting..."
mkfs.fat -F 32 -n boot "${PART}1"
mkswap -L swap "${PART}2"
mkfs.ext4 -L nixos -m 1 -F "${PART}3"
ok "Formatted"

# ── Mount ──
info "Mounting..."
mount /dev/disk/by-label/nixos /mnt
mkdir -p /mnt/boot
mount /dev/disk/by-label/boot /mnt/boot
swapon /dev/disk/by-label/swap
ok "Mounted"

# ── Generate hardware config ──
info "Generating hardware configuration..."
nixos-generate-config --root /mnt
ok "Hardware config generated at /mnt/etc/nixos/hardware-configuration.nix"

# ── Find flake on the ISO ──
# The ISO mounts the nix store which contains the flake source
FLAKE_PATH=""
for candidate in /iso /etc/nixos /home/aly/nalyx; do
  if [[ -f "$candidate/flake.nix" ]]; then
    FLAKE_PATH="$candidate"
    break
  fi
done

if [[ -z "$FLAKE_PATH" ]]; then
  die "Could not find flake.nix on the ISO"
fi

info "Using flake at: $FLAKE_PATH"

# ── Copy hardware config to flake ──
cp /mnt/etc/nixos/hardware-configuration.nix "$FLAKE_PATH/hosts/homelab/hardware-configuration.nix"
ok "Hardware config copied to flake"

# ── Install ──
info "Installing NixOS (this takes a while)..."
echo ""
nixos-install --flake "$FLAKE_PATH#homelab" --no-root-passwd
ok "NixOS installed!"

echo ""
echo -e "${GREEN}╔══════════════════════════════════════╗${NC}"
echo -e "${GREEN}║     Installation complete!            ║${NC}"
echo -e "${GREEN}║                                       ║${NC}"
echo -e "${GREEN}║  1. Run: sudo reboot                  ║${NC}"
echo -e "${GREEN}║  2. Login: aly / changeme              ║${NC}"
echo -e "${GREEN}║  3. WiFi connects automatically       ║${NC}"
echo -e "${GREEN}║  4. Tailscale: sudo tailscale up       ║${NC}"
echo -e "${GREEN}║                                       ║${NC}"
echo -e "${GREEN}║  After first boot, clone private repo  ║${NC}"
echo -e "${GREEN}║  and switch for full config.           ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════╝${NC}"

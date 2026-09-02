#!/usr/bin/env bash
# Guided nalyx installer, run from the live ISO as `nalyx-install`.
#
# Calamares is not an option here: calamares-nixos-extensions builds a vanilla
# configuration.nix from Python string templates and installs that, so it
# cannot install a flake host. It would produce a NixOS with no lanzaboote, no
# private modules and no desktop config. This drives the real flake instead.
#
# The disk is never typed. It is picked from a numbered list that shows model,
# size and serial, any disk carrying a Windows bootloader is refused outright,
# and the confirmation is the target's own serial suffix so a wrong row cannot
# be confirmed by reflex.
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info() { echo -e "${CYAN}[INFO]${NC} $*"; }
ok() { echo -e "${GREEN}[OK]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
die() {
  echo -e "${RED}[ERROR]${NC} $*" >&2
  exit 1
}

[[ $EUID -eq 0 ]] || die "run as root: sudo nalyx-install"

# Named up front so a missing tool is a loud failure here, not a safety check
# that quietly passes later. The Windows detection below is the reason: a
# check that cannot run must stop the install, never wave the disk through.
for tool in lsblk findmnt parted wipefs mkfs.fat mkfs.ext4 udevadm git nixos-install nixos-generate-config; do
  command -v "$tool" >/dev/null || die "missing required tool: $tool"
done

# Baked in by the generator so one script serves every image. Read from a file
# rather than interpolated into the script, so bash ${...} stays bash.
HOST_FILE=/etc/nalyx-install-host
[[ -r "$HOST_FILE" ]] || die "$HOST_FILE missing, is this the nalyx ISO?"
HOST=$(tr -d '[:space:]' <"$HOST_FILE")
[[ -n "$HOST" ]] || die "$HOST_FILE is empty"

REPO_URL=${NALYX_REPO_URL:-https://github.com/alysnnix/nalyx}
PRIVATE_SRC=${NALYX_PRIVATE_SRC:-/iso/nalyx-private}
ESP_MIB=1024

echo ""
echo -e "${BOLD}nalyx installer${NC}  host: ${CYAN}${HOST}${NC}"
echo ""

# ── Disk inventory ───────────────────────────────────────────────────────────
# A disk is disqualified when it holds a Windows bootloader or an NTFS volume.
# That is the whole safety story: the machine this targets dual boots, and the
# failure mode being designed out is erasing the wrong drive.
mapfile -t DISKS < <(lsblk -dpno NAME,TYPE | awk '$2 == "disk" { print $1 }')
[[ ${#DISKS[@]} -gt 0 ]] || die "no disks found"

# The live medium must never be a target.
LIVE_SRC=$(findmnt -no SOURCE /iso 2>/dev/null || true)
LIVE_DISK=""
if [[ -n "$LIVE_SRC" ]]; then
  LIVE_DISK=$(lsblk -dpno PKNAME "$LIVE_SRC" 2>/dev/null || true)
  [[ -n "$LIVE_DISK" ]] && LIVE_DISK="/dev/$LIVE_DISK"
fi

declare -a CAND_DEV CAND_LABEL
echo -e "${BOLD}disks${NC}"
echo ""
idx=0
for d in "${DISKS[@]}"; do
  size=$(lsblk -dno SIZE "$d" | tr -d ' ')
  model=$(lsblk -dno MODEL "$d" | sed 's/[[:space:]]*$//')
  serial=$(lsblk -dno SERIAL "$d" | tr -d ' ')
  [[ -n "$model" ]] || model="(unknown model)"
  [[ -n "$serial" ]] || serial="(no serial)"

  reason=""
  # Deliberately tool-free: PARTTYPE and FSTYPE both come from lsblk and blkid,
  # which are always on an installer image. An earlier version shelled out to
  # mtools to look for /EFI/Microsoft, which is not on the ISO, so the check
  # would have failed open and offered up the Windows disk.
  #
  # A real Windows install always carries the Microsoft Reserved partition and
  # a recovery partition, and its system volume is NTFS. Any one is enough.
  MSR_GUID=e3c9e316-0b5c-4db8-817d-f92df00215ae
  REC_GUID=de94bba4-06d1-4d40-a16a-bfd50179d6ac
  parttypes=$(lsblk -lno PARTTYPE "$d" | tr '[:upper:]' '[:lower:]')
  if grep -qx "$MSR_GUID" <<<"$parttypes"; then
    reason="microsoft reserved partition"
  elif grep -qx "$REC_GUID" <<<"$parttypes"; then
    reason="windows recovery partition"
  elif lsblk -lno FSTYPE "$d" | grep -qx ntfs; then
    reason="ntfs volume"
  fi
  if [[ -z "$reason" && -n "$LIVE_DISK" && "$d" == "$LIVE_DISK" ]]; then
    reason="live installer medium"
  fi

  if [[ -n "$reason" ]]; then
    printf "      %-14s %8s  %-26s %s\n" "$d" "$size" "$model" "$(echo -e "${RED}skipped: ${reason}${NC}")"
  else
    idx=$((idx + 1))
    CAND_DEV+=("$d")
    CAND_LABEL+=("$d  $size  $model  serial $serial")
    printf "  ${BOLD}%d)${NC}  %-14s %8s  %-26s serial %s\n" "$idx" "$d" "$size" "$model" "$serial"
  fi
done
echo ""

[[ ${#CAND_DEV[@]} -gt 0 ]] || die "every disk was skipped, nothing safe to install onto"

read -rp "target disk number: " PICK
[[ "$PICK" =~ ^[0-9]+$ ]] || die "not a number: $PICK"
[[ "$PICK" -ge 1 && "$PICK" -le ${#CAND_DEV[@]} ]] || die "no such option: $PICK"

DISK=${CAND_DEV[$((PICK - 1))]}
SERIAL=$(lsblk -dno SERIAL "$DISK" | tr -d ' ')
CONFIRM_TOKEN=${SERIAL: -4}
[[ -n "$CONFIRM_TOKEN" ]] || CONFIRM_TOKEN="ERASE"

echo ""
echo -e "${RED}${BOLD}this erases ${DISK} completely${NC}"
echo "  ${CAND_LABEL[$((PICK - 1))]}"
echo ""
echo "  new layout:"
echo "    1  ${ESP_MIB}MiB  fat32  NIXBOOT   EFI system partition"
echo "    2  rest      ext4   nixos     root"
echo ""
warn "physically unplugging the other disks is still the only guarantee"
echo ""
read -rp "type the last 4 of the serial (${CONFIRM_TOKEN}) to proceed: " ANSWER
[[ "$ANSWER" == "$CONFIRM_TOKEN" ]] || die "aborted, nothing was written"

# ── Partition ────────────────────────────────────────────────────────────────
if [[ "$DISK" == *nvme* || "$DISK" == *mmcblk* || "$DISK" == *loop* ]]; then
  P="${DISK}p"
else
  P="${DISK}"
fi

info "partitioning $DISK"
wipefs -a "$DISK" >/dev/null
parted -s "$DISK" -- mklabel gpt
parted -s "$DISK" -- mkpart ESP fat32 1MiB "${ESP_MIB}MiB"
parted -s "$DISK" -- set 1 esp on
parted -s "$DISK" -- mkpart root ext4 "${ESP_MIB}MiB" 100%
udevadm settle
ok "partitioned"

info "formatting"
mkfs.fat -F32 -n NIXBOOT "${P}1" >/dev/null
mkfs.ext4 -F -L nixos "${P}2" >/dev/null
udevadm settle
ok "formatted"

# ── Mount ────────────────────────────────────────────────────────────────────
# umask on the ESP is what bootctl and lanzaboote expect; without it they warn
# about a world readable ESP on every rebuild.
info "mounting"
mount "${P}2" /mnt
mkdir -p /mnt/boot
mount -o umask=0077 "${P}1" /mnt/boot
ok "mounted"

# ── Hardware config ──────────────────────────────────────────────────────────
info "scanning hardware"
nixos-generate-config --root /mnt
ok "hardware config generated"

# ── Flake ────────────────────────────────────────────────────────────────────
# The repo lands where update-sys.sh expects it (FLAKE_DIR="$HOME/nalyx"), so
# `switch` works after the first boot with no move.
USER_NAME=${NALYX_USER:-aly}
FLAKE_DIR="/mnt/home/${USER_NAME}/nalyx"

info "cloning $REPO_URL"
mkdir -p "$(dirname "$FLAKE_DIR")"
rm -rf "$FLAKE_DIR"
git clone --depth 1 "$REPO_URL" "$FLAKE_DIR"
ok "cloned to ${FLAKE_DIR#/mnt}"

# Overwrite the tracked file. Nix only sees version controlled paths in a git
# flake, so a differently named copy would be ignored and the install would use
# another machine's UUIDs.
HW_TARGET="$FLAKE_DIR/hosts/${HOST}/hardware-configuration.nix"
[[ -f "$HW_TARGET" ]] || die "no hosts/${HOST}/hardware-configuration.nix to overwrite"
cp /mnt/etc/nixos/hardware-configuration.nix "$HW_TARGET"
ok "hardware config placed for host ${HOST}"

# ── Private input ────────────────────────────────────────────────────────────
# Copied off the ISO rather than fetched: the locked input is an ssh:// URL and
# the live environment has no key. Copying it into the new system also means
# the first rebuild after boot works before any key exists.
INSTALL_ARGS=()
if [[ -d "$PRIVATE_SRC" && -f "$PRIVATE_SRC/flake.nix" ]]; then
  mkdir -p "$FLAKE_DIR/.private"
  rm -rf "$FLAKE_DIR/.private/nalyx-private"
  cp -r "$PRIVATE_SRC" "$FLAKE_DIR/.private/nalyx-private"
  chmod -R u+w "$FLAKE_DIR/.private/nalyx-private"
  INSTALL_ARGS+=(--override-input private "path:$FLAKE_DIR/.private/nalyx-private")
  ok "private input taken from the image"
else
  warn "no private input at $PRIVATE_SRC"
  warn "installing with public defaults: password will be 'changeme', no secrets"
fi

# ── Install ──────────────────────────────────────────────────────────────────
info "installing host ${HOST}, this takes a while"
echo ""
nixos-install --flake "${FLAKE_DIR}#${HOST}" --no-root-passwd "${INSTALL_ARGS[@]}"
ok "installed"

# HM activation runs as the user and fails on a root owned home.
IDS=$(awk -F: -v u="$USER_NAME" '$1 == u { print $3 ":" $4 }' /mnt/etc/passwd)
[[ -n "$IDS" ]] || die "user $USER_NAME not found in the installed /etc/passwd"
UID_N=${IDS%%:*}
GID_N=${IDS##*:}
chown -R "$UID_N:$GID_N" "/mnt/home/${USER_NAME}"
ok "home ownership fixed for $USER_NAME"

echo ""
echo -e "${GREEN}${BOLD}installation complete${NC}"
echo ""
echo -e "  ${BOLD}next, for Secure Boot${NC}"
echo "    1  reboot, leaving Secure Boot OFF or in Setup Mode"
echo "    2  log in as $USER_NAME with your own password"
echo "    3  sudo nixos-rebuild switch --flake ~/nalyx#${HOST} \\"
echo "         --override-input private \"path:\$HOME/nalyx/.private/nalyx-private\""
echo "    4  sudo sbctl verify        # every file under /boot must say signed"
echo "    5  sudo reboot              # the keys enroll here, in Setup Mode"
echo "    6  turn Secure Boot ON in the firmware"
echo "    7  bootctl status           # expect: Secure Boot: enabled (user)"
echo ""
echo "  then drop ~/.ssh/id_ed25519 in place and run switch, so sops takes over"
echo ""

#!/usr/bin/env bash

# BLACK-XBERecomp-Linux - Automated build script for Arch Linux
# Based on datfooldive's Linux fork
# https://github.com/datfooldive/BLACK-XBERecomp-Linux

set -e

BLUE='\033[1;34m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
NC='\033[0m'

# ------------------------------------------------------------------
# Detect repo root: works if script is in scripts/ or repo root.
# ------------------------------------------------------------------
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if [ "$(basename -- "$SCRIPT_DIR")" = "scripts" ]; then
  REPO_ROOT="$(dirname -- "$SCRIPT_DIR")"
else
  REPO_ROOT="$SCRIPT_DIR"
fi

GAME_SRC="$REPO_ROOT/game"

FORK_DIR="$HOME/BLACK-XBERecomp-Linux"
ASSETS_DIR="$FORK_DIR/assets"
EXEC_PATH="$FORK_DIR/out/build/release/black"

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}  BLACK-XBERecomp-Linux | Arch Linux Setup${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""
echo -e "${YELLOW}[INFO]${NC} Repo root:   $REPO_ROOT"
echo -e "${YELLOW}[INFO]${NC} Game folder: $GAME_SRC"
echo ""

if [ "$EUID" -eq 0 ]; then
  echo -e "${RED}[ERROR]${NC} Do not run this script as root. Use your normal user."
  exit 1
fi

# ------------------------------------------------------------------
# 1/6 Dependencies (base + yay + extract-xiso)
# ------------------------------------------------------------------
echo -e "${YELLOW}[1/6]${NC} Installing base dependencies..."
sudo pacman -S --needed --noconfirm \
  base-devel clang lld cmake ninja git pkgconf \
  vulkan-headers vulkan-icd-loader shaderc sdl3 \
  libx11 libxext libxrandr libxcursor libxi libxkbcommon \
  wayland wayland-protocols pipewire alsa-lib libpulse
echo -e "${GREEN}[OK]${NC} Base dependencies installed."

# --- yay ---
echo -e "${YELLOW}[INFO]${NC} Checking for yay (AUR helper)..."
if command -v yay &>/dev/null; then
  echo -e "${GREEN}[OK]${NC} yay is already installed."
else
  echo -e "${YELLOW}[INFO]${NC} yay not found. Installing from AUR..."
  TMP_YAY="$(mktemp -d)"
  git clone https://aur.archlinux.org/yay.git "$TMP_YAY/yay"
  (cd "$TMP_YAY/yay" && makepkg -si --noconfirm)
  rm -rf "$TMP_YAY"
  echo -e "${GREEN}[OK]${NC} yay installed."
fi

# --- extract-xiso ---
echo -e "${YELLOW}[INFO]${NC} Installing extract-xiso..."
if command -v extract-xiso &>/dev/null; then
  echo -e "${GREEN}[OK]${NC} extract-xiso is already installed."
else
  yay -S --needed --noconfirm extract-xiso
  echo -e "${GREEN}[OK]${NC} extract-xiso installed."
fi
echo ""

# ------------------------------------------------------------------
# 2/6 Clone fork (fresh by default; KEEP_FORK=1 to preserve)
# ------------------------------------------------------------------
echo -e "${YELLOW}[2/6]${NC} Preparing fork: $FORK_DIR"

if [ "${KEEP_FORK:-0}" = "1" ] && [ -d "$FORK_DIR" ]; then
  echo -e "${YELLOW}[INFO]${NC} KEEP_FORK=1 — reusing existing clone."
else
  if [ -d "$FORK_DIR" ]; then
    echo -e "${YELLOW}[INFO]${NC} Removing existing fork: $FORK_DIR"
    rm -rf -- "$FORK_DIR"
    echo -e "${GREEN}[OK]${NC} Removed."
  fi
  git clone https://github.com/datfooldive/BLACK-XBERecomp-Linux.git "$FORK_DIR"
  echo -e "${GREEN}[OK]${NC} Fork cloned to $FORK_DIR"
fi
echo ""

# ------------------------------------------------------------------
# 3/6 Game files — search for XISOs, then validate game/
# ------------------------------------------------------------------
echo -e "${YELLOW}[3/6]${NC} Preparing game files in: $GAME_SRC"
mkdir -p "$GAME_SRC"

# --- 3a) Search for Black XISO/ISO files ---
echo -e "${YELLOW}[INFO]${NC} Searching for Black XISO/ISO files..."

SEARCH_DIRS=(
  "$HOME/Downloads"
  "$HOME/Games"
  "$HOME/ISOs"
  "$HOME/Desktop"
  "$HOME"
  "$REPO_ROOT"
)

XISO_FILES=()
for dir in "${SEARCH_DIRS[@]}"; do
  [ -d "$dir" ] || continue
  while IFS= read -r -d '' f; do
    XISO_FILES+=("$f")
  done < <(find "$dir" -maxdepth 3 -type f \( -iname '*black*.iso' -o -iname '*black*.xiso' \) -print0 2>/dev/null)
done

if [ ${#XISO_FILES[@]} -eq 0 ]; then
  echo -e "${YELLOW}[INFO]${NC} No Black XISO/ISO files found in common locations."
else
  echo -e "${GREEN}[FOUND]${NC} ${#XISO_FILES[@]} file(s) found:"
  for f in "${XISO_FILES[@]}"; do
    echo "  - $f"
  done
  echo ""

  for f in "${XISO_FILES[@]}"; do
    read -p "Extract \"$(basename "$f")\" to $GAME_SRC? [y/N]: " EXTRACT
    if [[ "$EXTRACT" =~ ^[Yy]$ ]]; then
      echo -e "${YELLOW}[INFO]${NC} Extracting: $(basename "$f") ..."
      extract-xiso -x "$f" -d "$GAME_SRC"
      echo -e "${GREEN}[OK]${NC} Extracted: $(basename "$f")"
    else
      echo -e "${YELLOW}[SKIP]${NC} Skipped: $(basename "$f")"
    fi
  done
fi
echo ""

# --- 3b) Validate game/ has files (no default.xbe requirement) ---
has_game_files() {
  local dir="$1"
  [ -d "$dir" ] || return 1
  find "$dir" -maxdepth 1 -type f \
       ! -name 'README.md' \
       ! -name '.gitkeep' \
       | head -1 | grep -q .
}

while ! has_game_files "$GAME_SRC"; do
  echo ""
  echo -e "${YELLOW}──────────────────────────────────────────────${NC}"
  echo -e "${YELLOW}  GAME FILES REQUIRED${NC}"
  echo -e "${YELLOW}──────────────────────────────────────────────${NC}"
  echo ""
  echo -e "Put the extracted Black (USA/EU) files into:"
  echo -e "  ${BLUE}$GAME_SRC${NC}"
  echo ""
  echo -e "  ${GREEN}default.xbe${NC} should be directly inside that folder."
  echo ""
  echo -e "  Other options:"
  echo -e "    ${GREEN}A)${NC} Type a full path to a folder that already contains the game"
  echo -e "    ${GREEN}B)${NC} Type 'skip' to abort"
  echo ""

  read -e -p "Path (or ENTER after copying files into $GAME_SRC): " USER_PATH
  USER_PATH="${USER_PATH%/}"

  if [ "$USER_PATH" = "skip" ]; then
    echo -e "${RED}[ABORT]${NC} User aborted."
    exit 1
  fi

  if [ -n "$USER_PATH" ]; then
    if [ -d "$USER_PATH" ] && has_game_files "$USER_PATH"; then
      echo -e "${YELLOW}[INFO]${NC} Copying from $USER_PATH to $GAME_SRC..."
      rsync -ah --info=progress2 "$USER_PATH"/ "$GAME_SRC"/
      echo -e "${GREEN}[OK]${NC} Files copied."
    else
      echo -e "${RED}[ERROR]${NC} No game files found in: $USER_PATH"
    fi
  else
    if ! has_game_files "$GAME_SRC"; then
      echo ""
      echo -e "${YELLOW}[WAITING]${NC} Nothing yet in: $GAME_SRC"
      read -p "Press ENTER when ready (or type 'skip' to abort): " CONFIRM
      if [ "$CONFIRM" = "skip" ]; then
        echo -e "${RED}[ABORT]${NC} User aborted."
        exit 1
      fi
    fi
  fi
done

echo -e "${GREEN}[OK]${NC} Game files detected in: $GAME_SRC"
echo ""

# --- 3c) Non-blocking warning if default.xbe missing ---
if [ ! -f "$GAME_SRC/default.xbe" ]; then
  echo -e "${YELLOW}[WARN]${NC} default.xbe not found in $GAME_SRC."
  echo -e "${YELLOW}[INFO]${NC}  The game likely won't boot without it."
  read -p "Continue build anyway? [y/N]: " CONTINUE
  if [[ ! "$CONTINUE" =~ ^[Yy]$ ]]; then
    echo -e "${RED}[ABORT]${NC} User aborted."
    exit 1
  fi
fi

# --- 3d) Copy game/ -> fork assets/ ---
echo -e "${YELLOW}[INFO]${NC} Copying game files to: $ASSETS_DIR"
rsync -ah --info=progress2 \
  --exclude='README.md' --exclude='.gitkeep' \
  "$GAME_SRC"/ "$ASSETS_DIR"/
echo -e "${GREEN}[OK]${NC} Assets copied."
echo ""

# ------------------------------------------------------------------
# 4/6 Build
# ------------------------------------------------------------------
echo -e "${YELLOW}[4/6]${NC} Building BLACK-XBERecomp-Linux..."
echo -e "${YELLOW}[INFO]${NC} First build can take 15 - 60 minutes depending on your CPU."
echo ""
cd "$FORK_DIR"
chmod +x build.sh
./build.sh
echo -e "${GREEN}[OK]${NC} Build completed."
echo ""

# ------------------------------------------------------------------
# 5/6 Shortcut
# ------------------------------------------------------------------
echo -e "${YELLOW}[5/6]${NC} Creating application shortcut..."

if [ ! -x "$EXEC_PATH" ]; then
  echo -e "${RED}[WARN]${NC} Executable not found at $EXEC_PATH"
  echo -e "${YELLOW}[INFO]${NC} Skipping shortcut creation."
else
  APPS_DIR="$HOME/.local/share/applications"
  ICON_DIR="$HOME/.local/share/icons/hicolor/256x256/apps"
  DESKTOP_FILE="$APPS_DIR/black-xberecomp.desktop"
  ICON_TARGET_NAME="black-xberecomp"

  mkdir -p "$APPS_DIR" "$ICON_DIR"

  FOUND_ICON=""
  for candidate in \
    "$GAME_SRC/icon.png" \
    "$GAME_SRC/logo.png" \
    "$REPO_ROOT/icon.png" \
    "$REPO_ROOT/logo.png" \
    "$ASSETS_DIR/icon.png" \
    "$ASSETS_DIR/logo.png" \
    "$FORK_DIR/icon.png" \
    "$FORK_DIR/data/icon.png" \
    "$FORK_DIR/resources/icon.png"; do
    if [ -f "$candidate" ]; then
      FOUND_ICON="$candidate"
      break
    fi
  done

  if [ -n "$FOUND_ICON" ]; then
    cp "$FOUND_ICON" "$ICON_DIR/$ICON_TARGET_NAME.png"
    ICON_FIELD="$ICON_TARGET_NAME"
    echo -e "${GREEN}[OK]${NC} Icon installed from: $FOUND_ICON"
  else
    ICON_FIELD="applications-games"
    echo -e "${YELLOW}[INFO]${NC} Using system icon."
  fi

  cat > "$DESKTOP_FILE" <<DESKTOP_EOF
[Desktop Entry]
Type=Application
Version=1.0
Name=BLACK (XBE Recomp)
GenericName=Xbox Game
Comment=Xbox game BLACK recompiled for Linux
Exec=$EXEC_PATH
TryExec=$EXEC_PATH
Path=$FORK_DIR
Icon=$ICON_FIELD
Terminal=false
Categories=Game;ActionGame;
Keywords=black;xbox;xbe;recomp;
StartupNotify=true
DESKTOP_EOF

  chmod +x "$DESKTOP_FILE"
  echo -e "${GREEN}[OK]${NC} Menu shortcut: $DESKTOP_FILE"

  command -v update-desktop-database &>/dev/null && update-desktop-database "$APPS_DIR" 2>/dev/null || true
  command -v gtk-update-icon-cache &>/dev/null && gtk-update-icon-cache -q -t -f "$HOME/.local/share/icons/hicolor" 2>/dev/null || true

  DESKTOP_DIR="$(xdg-user-dir DESKTOP 2>/dev/null || echo "$HOME/Desktop")"
  if [ -d "$DESKTOP_DIR" ]; then
    read -p "Also create a shortcut on the Desktop? [y/N]: " MAKE_DESK
    if [[ "$MAKE_DESK" =~ ^[Yy]$ ]]; then
      cp "$DESKTOP_FILE" "$DESKTOP_DIR/black-xberecomp.desktop"
      chmod +x "$DESKTOP_DIR/black-xberecomp.desktop"
      command -v gio &>/dev/null && gio set "$DESKTOP_DIR/black-xberecomp.desktop" metadata::trusted true 2>/dev/null || true
      echo -e "${GREEN}[OK]${NC} Desktop shortcut created."
    fi
  fi
fi
echo ""

# ------------------------------------------------------------------
# 6/6 Done
# ------------------------------------------------------------------
echo -e "${YELLOW}[6/6]${NC} All done!"
echo -e "${BLUE}============================================${NC}"
echo -e "${GREEN}Executable:${NC}   $EXEC_PATH"
echo -e "${GREEN}Run with:${NC}     cd $FORK_DIR && ./out/build/release/black"
echo -e "${GREEN}App shortcut:${NC} Search \"BLACK\" in your application menu"
echo -e "${GREEN}Saves/Config:${NC} Created next to the executable (hdd/, black.toml)"
echo -e "${GREEN}Settings:${NC}     Press F10 in-game"
echo -e "${BLUE}============================================${NC}"

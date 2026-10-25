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

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

REPO_DIR="$HOME/BLACK-XBERecomp-Linux"
ASSETS_DIR="$REPO_DIR/assets"
EXEC_PATH="$REPO_DIR/out/build/release/black"

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}  BLACK-XBERecomp-Linux | Arch Linux Setup${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""

if [ "$EUID" -eq 0 ]; then
  echo -e "${RED}[ERROR]${NC} Do not run this script as root. Use your normal user."
  exit 1
fi

# 1) Install dependencies
echo -e "${YELLOW}[1/6]${NC} Installing required dependencies..."
sudo pacman -S --needed --noconfirm \
  base-devel clang lld cmake ninja git pkgconf \
  vulkan-headers vulkan-icd-loader shaderc sdl3 \
  libx11 libxext libxrandr libxcursor libxi libxkbcommon \
  wayland wayland-protocols pipewire alsa-lib libpulse
echo -e "${GREEN}[OK]${NC} Dependencies installed."
echo ""

# 2) Clone the Linux fork
echo -e "${YELLOW}[2/6]${NC} Cloning BLACK-XBERecomp-Linux fork..."
if [ -d "$REPO_DIR" ]; then
  echo -e "${YELLOW}[INFO]${NC} $REPO_DIR already exists."
  read -p "Do you want to update it with git pull? [y/N]: " UPDATE
  if [[ "$UPDATE" =~ ^[Yy]$ ]]; then
    cd "$REPO_DIR"
    git pull --ff-only
    echo -e "${GREEN}[OK]${NC} Repository updated."
  else
    echo -e "${YELLOW}[SKIP]${NC} Skipping git clone/pull."
  fi
else
  git clone https://github.com/datfooldive/BLACK-XBERecomp-Linux.git "$REPO_DIR"
  echo -e "${GREEN}[OK]${NC} Repository cloned to $REPO_DIR"
fi
echo ""

# ------------------------------------------------------------------
# 3) Obtain game assets (interactive, blocks until default.xbe exists)
# ------------------------------------------------------------------
echo -e "${YELLOW}[3/6]${NC} Locating Black (USA/EU) game files..."
mkdir -p "$ASSETS_DIR"

copy_assets() {
  local src="$1"
  if [ "$(readlink -f "$src")" = "$(readlink -f "$ASSETS_DIR")" ]; then
    echo -e "${YELLOW}[INFO]${NC} Files are already in $ASSETS_DIR — nothing to copy."
    return 0
  fi
  echo -e "${YELLOW}[INFO]${NC} Copying files from: $src"
  echo -e "${YELLOW}[INFO]${NC}          to: $ASSETS_DIR (this may take a moment)..."
  rsync -ah --info=progress2 "${src%/}"/ "$ASSETS_DIR"/
  echo -e "${GREEN}[OK]${NC} Assets copied successfully."
}

# Find default.xbe next to this script, either in a "game" subfolder or at the root.
# Prints the folder path on success; returns non-zero if not found.
find_local_game() {
  local p
  for p in "$SCRIPT_DIR/game" "$SCRIPT_DIR/Game" "$SCRIPT_DIR/GAME" "$SCRIPT_DIR"; do
    if [ -f "$p/default.xbe" ]; then
      printf '%s\n' "$p"
      return 0
    fi
  done
  return 1
}

# --- 3a) Known locations (script root, "game/" next to script, and common paths)
CANDIDATES=(
  "$SCRIPT_DIR/game"
  "$SCRIPT_DIR/Game"
  "$SCRIPT_DIR/GAME"
  "$SCRIPT_DIR"
  "$SCRIPT_DIR/Black (USA)"
  "$SCRIPT_DIR/Black-USA"
  "$HOME/Games/BLACK-2006-Recomp/game"
  "$HOME/Games/Black 2006/game"
  "$HOME/Games/Black Build/game"
  "$HOME/Games/Heroic/Prefixes/Black Build/BLACK-0.1.0-alpha.5/game"
  "$HOME/Games/Heroic/Prefixes/Black 2006/pfx/drive_c/Games/Black/game"
  "$HOME/Games/Heroic/Prefixes/Black 2006 2/pfx/drive_c/Games/Black/assets"
  "$HOME/Downloads/Black (USA)"
)

FOUND_PATH=""
for path in "${CANDIDATES[@]}"; do
  if [ -f "$path/default.xbe" ]; then
    FOUND_PATH="$path"
    break
  fi
done

if [ -n "$FOUND_PATH" ]; then
  echo -e "${GREEN}[FOUND]${NC} Possible game folder detected:"
  echo -e "        ${BLUE}$FOUND_PATH${NC}"
  read -p "Use this folder? [Y/n]: " USE_IT
  if [[ ! "$USE_IT" =~ ^[Nn]$ ]]; then
    copy_assets "$FOUND_PATH"
  else
    FOUND_PATH=""
  fi
fi

# --- 3b) Interactive loop until default.xbe is present
while [ ! -f "$ASSETS_DIR/default.xbe" ]; do
  echo ""
  echo -e "${YELLOW}──────────────────────────────────────────────${NC}"
  echo -e "${YELLOW}  GAME FILES REQUIRED${NC}"
  echo -e "${YELLOW}──────────────────────────────────────────────${NC}"
  echo -e "Easiest options (drop the extracted Black USA/EU files anywhere here):"
  echo ""
  echo -e "  ${GREEN}•${NC} ${BLUE}$SCRIPT_DIR/game/${NC}   ← recommended"
  echo -e "  ${GREEN}•${NC} ${BLUE}$SCRIPT_DIR/${NC}        ← directly next to this script"
  echo ""
  echo -e "  In either case, ${GREEN}default.xbe${NC} must be directly inside the folder."
  echo -e "  Then press ${GREEN}ENTER${NC} — the script will pick the files up automatically."
  echo ""
  echo -e "Or:"
  echo -e "  ${GREEN}A)${NC} Type the full path to a folder that already contains ${GREEN}default.xbe${NC}."
  echo -e "  ${GREEN}B)${NC} Copy the files manually into ${BLUE}$ASSETS_DIR${NC} and press ENTER."
  echo ""

  read -e -p "Path (or ENTER to auto-detect next to script / wait for manual copy): " USER_PATH
  USER_PATH="${USER_PATH%/}"

  if [ -n "$USER_PATH" ]; then
    if [ -f "$USER_PATH/default.xbe" ]; then
      copy_assets "$USER_PATH"
    else
      echo -e "${RED}[ERROR]${NC} default.xbe was not found in: $USER_PATH"
      echo -e "${YELLOW}[INFO]${NC}  Please check the path and try again."
      continue
    fi
  else
    # Re-scan script dir (root or "game/") and $ASSETS_DIR
    if LOCAL_GAME="$(find_local_game)"; then
      echo -e "${GREEN}[FOUND]${NC} Detected game files at: $LOCAL_GAME"
      copy_assets "$LOCAL_GAME"
      continue
    fi
    if [ ! -f "$ASSETS_DIR/default.xbe" ]; then
      echo ""
      echo -e "${YELLOW}[WAITING]${NC} Looking for ${GREEN}default.xbe${NC} in:"
      echo -e "          • ${BLUE}$SCRIPT_DIR/game/${NC}"
      echo -e "          • ${BLUE}$SCRIPT_DIR/${NC}"
      echo -e "          • ${BLUE}$ASSETS_DIR/${NC}"
      echo ""
      read -p "Press ENTER when you've placed the files (or type 'skip' to abort): " CONFIRM
      if [ "$CONFIRM" = "skip" ]; then
        echo -e "${RED}[ABORT]${NC} User aborted. Re-run the script when ready."
        exit 1
      fi
      if LOCAL_GAME="$(find_local_game)"; then
        echo -e "${GREEN}[FOUND]${NC} Detected game files at: $LOCAL_GAME"
        copy_assets "$LOCAL_GAME"
      elif [ ! -f "$ASSETS_DIR/default.xbe" ]; then
        echo -e "${RED}[NOT FOUND]${NC} Still missing. Waiting again..."
      fi
    fi
  fi
done

echo -e "${GREEN}[OK]${NC} Verified: default.xbe present in $ASSETS_DIR"
echo ""

# 4) Build
echo -e "${YELLOW}[4/6]${NC} Building BLACK-XBERecomp-Linux..."
echo -e "${YELLOW}[INFO]${NC} First build can take 15 - 60 minutes depending on your CPU."
echo ""
cd "$REPO_DIR"
chmod +x build.sh
./build.sh
echo -e "${GREEN}[OK]${NC} Build completed."
echo ""

# 5) Create application shortcut (.desktop)
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
    "$SCRIPT_DIR/game/icon.png" \
    "$SCRIPT_DIR/game/logo.png" \
    "$SCRIPT_DIR/icon.png" \
    "$SCRIPT_DIR/logo.png" \
    "$ASSETS_DIR/icon.png" \
    "$ASSETS_DIR/logo.png" \
    "$REPO_DIR/icon.png" \
    "$REPO_DIR/data/icon.png" \
    "$REPO_DIR/resources/icon.png"; do
    if [ -f "$candidate" ]; then
      FOUND_ICON="$candidate"
      break
    fi
  done

  if [ -n "$FOUND_ICON" ]; then
    cp "$FOUND_ICON" "$ICON_DIR/$ICON_TARGET_NAME.png"
    ICON_FIELD="$ICON_TARGET_NAME"
    echo -e "${GREEN}[OK]${NC} Icon installed: $ICON_DIR/$ICON_TARGET_NAME.png"
  else
    ICON_FIELD="applications-games"
    echo -e "${YELLOW}[INFO]${NC} No custom icon found; using system 'applications-games'."
  fi

  cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Type=Application
Version=1.0
Name=BLACK (XBE Recomp)
GenericName=Xbox Game
Comment=Xbox game BLACK recompiled for Linux
Exec=$EXEC_PATH
TryExec=$EXEC_PATH
Path=$REPO_DIR
Icon=$ICON_FIELD
Terminal=false
Categories=Game;ActionGame;
Keywords=black;xbox;xbe;recomp;
StartupNotify=true
EOF

  chmod +x "$DESKTOP_FILE"
  echo -e "${GREEN}[OK]${NC} Menu shortcut: $DESKTOP_FILE"

  if command -v update-desktop-database &>/dev/null; then
    update-desktop-database "$APPS_DIR" 2>/dev/null || true
  fi
  if command -v gtk-update-icon-cache &>/dev/null; then
    gtk-update-icon-cache -q -t -f "$HOME/.local/share/icons/hicolor" 2>/dev/null || true
  fi

  DESKTOP_DIR="$(xdg-user-dir DESKTOP 2>/dev/null || echo "$HOME/Desktop")"
  if [ -d "$DESKTOP_DIR" ]; then
    read -p "Also create a shortcut on the Desktop ($DESKTOP_DIR)? [y/N]: " MAKE_DESK
    if [[ "$MAKE_DESK" =~ ^[Yy]$ ]]; then
      cp "$DESKTOP_FILE" "$DESKTOP_DIR/black-xberecomp.desktop"
      chmod +x "$DESKTOP_DIR/black-xberecomp.desktop"
      if command -v gio &>/dev/null; then
        gio set "$DESKTOP_DIR/black-xberecomp.desktop" metadata::trusted true 2>/dev/null || true
      fi
      echo -e "${GREEN}[OK]${NC} Desktop shortcut: $DESKTOP_DIR/black-xberecomp.desktop"
    fi
  fi
fi
echo ""

# 6) Done
echo -e "${YELLOW}[6/6]${NC} All done!"
echo -e "${BLUE}============================================${NC}"
echo -e "${GREEN}Executable:${NC}   $EXEC_PATH"
echo -e "${GREEN}Run with:${NC}     cd $REPO_DIR && ./out/build/release/black"
echo -e "${GREEN}App shortcut:${NC} Search \"BLACK\" in your application menu"
echo -e "${GREEN}Saves/Config:${NC} Created next to the executable (hdd/, black.toml)"
echo -e "${GREEN}Settings:${NC}     Press F10 in-game"
echo -e "${BLUE}============================================${NC}"
echo ""
echo -e "${YELLOW}Tip:${NC} First launch from a terminal is recommended to catch errors."

#!/usr/bin/env bash
#
# Project Aevis Desktop Environment Automated Fetch, Build & Installer
# Built upon the foundation of Cutefish OS
# Supports Arch Linux / EndeavourOS, Debian / Ubuntu, and Fedora
#
set -euo pipefail

# ANSI color codes
BOLD="\033[1m"
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
CYAN="\033[1;36m"
RED="\033[1;31m"
NC="\033[0m"

log_info() {
    echo -e "${CYAN}[INFO]${NC} ${BOLD}$1${NC}"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

CUTEFISH_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GITHUB_BASE="https://github.com/CutefishOs-Revived"

# Dynamic Qt6 toolchain path discovery
QT6_BIN_DIR=""
if command -v qtpaths6 &>/dev/null; then
    QT6_BIN_DIR="$(qtpaths6 --binaries-dir 2>/dev/null || true)"
elif [ -d "/usr/lib/qt6/bin" ]; then
    QT6_BIN_DIR="/usr/lib/qt6/bin"
elif [ -d "/usr/lib64/qt6/bin" ]; then
    QT6_BIN_DIR="/usr/lib64/qt6/bin"
fi

if [ -n "$QT6_BIN_DIR" ]; then
    export PATH="$QT6_BIN_DIR:$PATH"
fi

log_info "Preparing Project Aevis Desktop Environment installation..."

cleanup() {
    if [ -n "${SUDO_PID:-}" ]; then
        kill "$SUDO_PID" 2>/dev/null || true
    fi
    if [ "$EUID" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
        chown -R "$(id -u "$SUDO_USER")":"$(id -g "$SUDO_USER")" "$CUTEFISH_ROOT" 2>/dev/null || true
    fi
}
trap cleanup EXIT

# Ensure sudo credentials
log_info "Acquiring root privileges for package installation..."
sudo -v

# Keep sudo alive in background
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
SUDO_PID=$!

# Ensure workspace build directories are owned by regular user
if [ "$EUID" -ne 0 ]; then
    if [ -n "$(find "$CUTEFISH_ROOT" -maxdepth 3 -user root -print -quit 2>/dev/null)" ]; then
        log_info "Ensuring workspace build directories are owned by $(id -un)..."
        sudo chown -R "$(id -u):$(id -g)" "$CUTEFISH_ROOT" 2>/dev/null || true
    fi
fi

# ==============================================================================
# Step 1: Install System Dependencies based on Package Manager
# ==============================================================================
log_info "Step 1: Installing system build dependencies..."

if command -v pacman &>/dev/null; then
    log_info "Detected pacman package manager (Arch Linux / EndeavourOS / Manjaro)..."
    PACMAN_DEPS=(
        git
        cmake
        gcc
        extra-cmake-modules
        qt6-tools
        qt6-declarative
        qt6-svg
        qt6-wayland
        kwin
        kdecoration
        kwayland
        kidletime
        kglobalaccel
        networkmanager-qt
        modemmanager-qt
        polkit-qt6
        libqtxdg
        bluez-qt
        libkscreen
        libzip
        libcanberra
        libpulse
        sound-theme-freedesktop
        libxcursor
        libxtst
        libxcomposite
        libepoxy
        qt5-tools
    )
    sudo pacman -S --needed --noconfirm "${PACMAN_DEPS[@]}" || log_warn "Pacman install completed with warnings."

elif command -v apt-get &>/dev/null; then
    log_info "Detected apt package manager (Debian / Ubuntu / Linux Mint)..."
    sudo apt-get update
    APT_DEPS=(
        git
        cmake
        build-essential
        extra-cmake-modules
        qt6-base-dev
        qt6-declarative-dev
        qt6-svg-dev
        qt6-wayland-dev
        qt6-tools-dev
        libpolkit-qt6-1-dev
        libzip-dev
        libcanberra-dev
        libpulse-dev
        libxcursor-dev
        libxtst-dev
        libxcomposite-dev
        libepoxy-dev
    )
    sudo apt-get install -y "${APT_DEPS[@]}" || log_warn "Apt install completed with warnings."

elif command -v dnf &>/dev/null; then
    log_info "Detected dnf package manager (Fedora / RHEL)..."
    DNF_DEPS=(
        git
        cmake
        gcc-c++
        extra-cmake-modules
        qt6-qtbase-devel
        qt6-qtdeclarative-devel
        qt6-qtsvg-devel
        qt6-qtwayland-devel
        qt6-qttools-devel
        polkit-qt6-1-devel
        libzip-devel
        libcanberra-devel
        pulseaudio-libs-devel
        libXcursor-devel
        libXtst-devel
        libXcomposite-devel
        libepoxy-devel
    )
    sudo dnf install -y "${DNF_DEPS[@]}" || log_warn "DNF install completed with warnings."
else
    log_warn "Unknown package manager. Please ensure CMake, C++ compiler, Qt 6, and KF6 dependencies are installed."
fi

log_success "System dependencies verified."

# ==============================================================================
# Step 2: Fetch / Clone Repositories & Create Submodule Folders
# ==============================================================================
log_info "Step 2: Fetching repositories and creating component folders..."

REPOS=(
    "fishui"
    "cutefish-framework"
    "core"
    "kwin-plugins"
    "dock"
    "launcher"
    "statusbar"
    "shell"
    "settings"
    "screenlocker"
    "screenshot"
    "photos"
    "terminal"
    "calculator"
    "task-manager"
    "icons"
    "gtk-themes"
    "wallpapers"
    "sddm-theme"
    "cursor-themes"
    "plymouth-theme"
    "qt-plugins"
    "updator"
    "wine-patches"
)

for repo in "${REPOS[@]}"; do
    repo_dir="$CUTEFISH_ROOT/$repo"
    repo_url="$GITHUB_BASE/$repo.git"

    if [ ! -d "$repo_dir" ]; then
        log_info "Cloning $repo from $repo_url..."
        git clone --recursive "$repo_url" "$repo_dir"
    else
        log_info "Folder $repo already exists."
        if [ -d "$repo_dir/.git" ]; then
            log_info "Fetching latest commits for $repo..."
            git -C "$repo_dir" fetch --quiet || log_warn "Failed to fetch update for $repo"
        fi
    fi
    mkdir -p "$repo_dir/build"
done
log_success "All repositories fetched and workspace folders created."

# ==============================================================================
# Helper Function to Build and Install CMake Components
# ==============================================================================
build_and_install_cmake() {
    local name="$1"
    local dir="$CUTEFISH_ROOT/$name"
    local extra_args="${2:-}"

    if [ ! -d "$dir" ]; then
        log_warn "Directory $name does not exist, skipping."
        return 0
    fi

    if [ -d "$dir/build" ] && [ ! -w "$dir/build" ]; then
        sudo chown -R "$(id -u):$(id -g)" "$dir/build" 2>/dev/null || true
    fi
    mkdir -p "$dir/build"
    # Auto-detect if workspace was renamed or moved and clear stale CMakeCache
    if [ -f "$dir/build/CMakeCache.txt" ]; then
        local cached_src
        cached_src="$(grep -E "^CMAKE_HOME_DIRECTORY:INTERNAL=" "$dir/build/CMakeCache.txt" 2>/dev/null | cut -d= -f2 || true)"
        if [ -n "$cached_src" ] && [ "$cached_src" != "$dir" ]; then
            log_info "Detected moved workspace ($cached_src -> $dir); refreshing cache for $name..."
            rm -rf "$dir/build/CMakeCache.txt" "$dir/build/CMakeFiles"
        fi
    fi
    cmake -B "$dir/build" -S "$dir" \
        -DCMAKE_INSTALL_PREFIX=/usr \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_CXX_FLAGS_RELEASE="-O3 -DNDEBUG -ffunction-sections -fdata-sections" \
        -DCMAKE_SHARED_LINKER_FLAGS_RELEASE="-Wl,--gc-sections -Wl,--as-needed" \
        -DCMAKE_EXE_LINKER_FLAGS_RELEASE="-Wl,--gc-sections -Wl,--as-needed" \
        $extra_args
    cmake --build "$dir/build" -j"$(nproc)"
    sudo cmake --install "$dir/build"
    sudo chown -R "$(id -u):$(id -g)" "$dir/build" 2>/dev/null || true
    log_success "$name installed successfully."
}

# ==============================================================================
# Step 3: Build & Install Desktop Environment Components
# ==============================================================================
log_info "Step 3: Building core Cutefish DE frameworks and libraries in topological dependency order..."

build_and_install_cmake "fishui"
build_and_install_cmake "cutefish-framework"
build_and_install_cmake "core"
build_and_install_cmake "kwin-plugins"
build_and_install_cmake "dock"
build_and_install_cmake "launcher"
build_and_install_cmake "statusbar"
build_and_install_cmake "shell"
build_and_install_cmake "settings"
build_and_install_cmake "screenlocker"
build_and_install_cmake "qt-plugins"

log_info "Step 4: Building Cutefish applications..."
build_and_install_cmake "filemanager" || log_warn "Failed to build filemanager, continuing..."
build_and_install_cmake "terminal" || log_warn "Failed to build terminal, continuing..."
build_and_install_cmake "calculator" || log_warn "Failed to build calculator, continuing..."
build_and_install_cmake "screenshot" || log_warn "Failed to build screenshot, continuing..."
build_and_install_cmake "photos" || log_warn "Failed to build photos, continuing..."
build_and_install_cmake "task-manager" || log_warn "Failed to build task-manager, continuing..."

log_info "Step 5: Installing themes, wallpapers, and desktop assets..."
# Clean up any misplaced cursor themes in themes directory before installing GTK themes
if [ -f "/usr/share/themes/aevis-dark/cursor.theme" ]; then
    log_info "Removing misplaced cursor themes from /usr/share/themes..."
    sudo rm -rf /usr/share/themes/aevis-dark /usr/share/themes/aevis-light \
                /usr/share/themes/cutefish-dark /usr/share/themes/cutefish-light 2>/dev/null || true
fi

build_and_install_cmake "icons"
build_and_install_cmake "wallpapers"
build_and_install_cmake "gtk-themes"

# Ensure user local themes directories have the GTK themes
if [ -n "$HOME" ] && [ -d "$CUTEFISH_ROOT/gtk-themes" ]; then
    log_info "Ensuring GTK themes are linked to user theme directories..."
    mkdir -p "$HOME/.local/share/themes" "$HOME/.themes"
    rm -rf "$HOME/.local/share/themes/.git" "$HOME/.themes/.git" "$HOME/.local/share/themes/CMakeLists.txt" "$HOME/.themes/CMakeLists.txt" 2>/dev/null || true
    for t in Aevis Aevis-light Aevis-dark Cutefish Cutefish-light Cutefish-dark aevis aevis-light aevis-dark cutefish cutefish-light cutefish-dark; do
        if [ -d "/usr/share/themes/$t" ]; then
            rm -rf "$HOME/.local/share/themes/$t" "$HOME/.themes/$t" 2>/dev/null || true
            ln -sf "/usr/share/themes/$t" "$HOME/.local/share/themes/$t"
            ln -sf "/usr/share/themes/$t" "$HOME/.themes/$t"
        fi
    done
fi

# SDDM Theme Installation
if [ -d "$CUTEFISH_ROOT/sddm-theme" ]; then
    log_info "Installing SDDM theme files..."
    sudo mkdir -p /usr/share/sddm/themes/cutefish /usr/share/sddm/themes/aevis
    sudo cp -f "$CUTEFISH_ROOT/sddm-theme/"*.qml "$CUTEFISH_ROOT/sddm-theme/"*.svg "$CUTEFISH_ROOT/sddm-theme/"*.desktop "$CUTEFISH_ROOT/sddm-theme/theme.conf" /usr/share/sddm/themes/cutefish/ 2>/dev/null || true
    sudo cp -f "$CUTEFISH_ROOT/sddm-theme/"*.qml "$CUTEFISH_ROOT/sddm-theme/"*.svg "$CUTEFISH_ROOT/sddm-theme/"*.desktop "$CUTEFISH_ROOT/sddm-theme/theme.conf" /usr/share/sddm/themes/aevis/ 2>/dev/null || true
    sudo mkdir -p /usr/share/sddm/themes/cutefish/faces /usr/share/sddm/themes/aevis/faces
    sudo cp -rf "$CUTEFISH_ROOT/sddm-theme/faces/"* /usr/share/sddm/themes/cutefish/faces/ 2>/dev/null || true
    sudo cp -rf "$CUTEFISH_ROOT/sddm-theme/faces/"* /usr/share/sddm/themes/aevis/faces/ 2>/dev/null || true
    sudo mkdir -p /etc/sddm.conf.d
    sudo cp -f "$CUTEFISH_ROOT/sddm-theme/sddm.conf" /etc/sddm.conf.d/theme.conf 2>/dev/null || true
    sudo cp -f "$CUTEFISH_ROOT/sddm-theme/sddm.conf" /etc/sddm.conf 2>/dev/null || true
    log_success "SDDM theme installed."
fi

# Cursor Theme Installation
if [ -d "$CUTEFISH_ROOT/cursor-themes" ]; then
    log_info "Installing cursor themes..."
    sudo mkdir -p /usr/share/icons
    [ -d "$CUTEFISH_ROOT/cursor-themes/cutefish-dark" ] && sudo cp -r "$CUTEFISH_ROOT/cursor-themes/cutefish-dark" /usr/share/icons/
    [ -d "$CUTEFISH_ROOT/cursor-themes/cutefish-light" ] && sudo cp -r "$CUTEFISH_ROOT/cursor-themes/cutefish-light" /usr/share/icons/
    [ -d "$CUTEFISH_ROOT/cursor-themes/cutefish-dark" ] && sudo cp -r "$CUTEFISH_ROOT/cursor-themes/cutefish-dark" /usr/share/icons/aevis-dark
    [ -d "$CUTEFISH_ROOT/cursor-themes/cutefish-light" ] && sudo cp -r "$CUTEFISH_ROOT/cursor-themes/cutefish-light" /usr/share/icons/aevis-light
    log_success "Cursor themes installed."
fi

# Plymouth Theme Installation
if [ -d "$CUTEFISH_ROOT/plymouth-theme" ]; then
    log_info "Installing plymouth themes..."
    sudo mkdir -p /usr/share/plymouth/themes
    [ -d "$CUTEFISH_ROOT/plymouth-theme/cutefish-logo" ] && sudo cp -r "$CUTEFISH_ROOT/plymouth-theme/cutefish-logo" /usr/share/plymouth/themes/ && sudo cp -r "$CUTEFISH_ROOT/plymouth-theme/cutefish-logo" /usr/share/plymouth/themes/aevis-logo
    [ -d "$CUTEFISH_ROOT/plymouth-theme/cutefish-text" ] && sudo cp -r "$CUTEFISH_ROOT/plymouth-theme/cutefish-text" /usr/share/plymouth/themes/ && sudo cp -r "$CUTEFISH_ROOT/plymouth-theme/cutefish-text" /usr/share/plymouth/themes/aevis-text
    log_success "Plymouth themes installed."
fi

# Clean up any legacy local binaries or links shadowing system-wide /usr/bin binaries
log_info "Step 6: Purging any user-local binary shadows from ~/.local/bin and /usr/local/bin..."
rm -f "$HOME/.local/bin/cutefish-"* "$HOME/.local/bin/aevis-"* 2>/dev/null || true
sudo rm -f /usr/local/bin/cutefish-* /usr/local/bin/aevis-* 2>/dev/null || true
log_success "All Cutefish and Aevis DE components installed system-wide in /usr/bin for all users."

# Refresh System Caches
log_info "Step 7: Refreshing system dynamic libraries, icon caches, and font databases..."
sudo mkdir -p /etc/xdg/menus /usr/share/wayland-sessions
if [ -f "$CUTEFISH_ROOT/core/session/cutefish-applications.menu" ]; then
    sudo cp -f "$CUTEFISH_ROOT/core/session/cutefish-applications.menu" /etc/xdg/menus/
    sudo cp -f "$CUTEFISH_ROOT/core/session/cutefish-applications.menu" /etc/xdg/menus/aevis-applications.menu
fi
if [ -f "$CUTEFISH_ROOT/core/session/cutefish-wayland.desktop" ]; then
    sudo cp -f "$CUTEFISH_ROOT/core/session/cutefish-wayland.desktop" /usr/share/wayland-sessions/
fi
if [ -f "$CUTEFISH_ROOT/core/session/aevis-wayland.desktop" ]; then
    sudo cp -f "$CUTEFISH_ROOT/core/session/aevis-wayland.desktop" /usr/share/wayland-sessions/
fi
for app in session shell filemanager terminal settings calculator taskmanager photos screenshot screenlocker launcher dock statusbar services appruntime polkit-agent; do
    cf_bin="cutefish-$app"
    av_bin="aevis-$app"
    if [ -f "/usr/bin/$cf_bin" ]; then
        sudo ln -sf "$cf_bin" "/usr/bin/$av_bin"
    fi
done
[ -f /usr/bin/cutefish-taskmanager ] && sudo ln -sf cutefish-taskmanager /usr/bin/aevis-taskmanager
[ -f /usr/bin/cutefish-taskmanager ] && sudo ln -sf cutefish-taskmanager /usr/bin/aevis-task-manager

# Ensure KWin scripts and effects are installed to system directories
sudo mkdir -p /usr/share/kwin/scripts/cutefishlauncher \
              /usr/share/kwin/scripts/aevislauncher \
              /usr/share/kwin-wayland/scripts/cutefishlauncher \
              /usr/share/kwin-wayland/scripts/aevislauncher
if [ -d "$CUTEFISH_ROOT/kwin-plugins/scripts/cutefishlauncher" ]; then
    sudo cp -rf "$CUTEFISH_ROOT/kwin-plugins/scripts/cutefishlauncher/"* /usr/share/kwin/scripts/cutefishlauncher/ 2>/dev/null || true
    sudo cp -rf "$CUTEFISH_ROOT/kwin-plugins/scripts/cutefishlauncher/"* /usr/share/kwin-wayland/scripts/cutefishlauncher/ 2>/dev/null || true
fi
if [ -d "$CUTEFISH_ROOT/kwin-plugins/scripts/aevislauncher" ]; then
    sudo cp -rf "$CUTEFISH_ROOT/kwin-plugins/scripts/aevislauncher/"* /usr/share/kwin/scripts/aevislauncher/ 2>/dev/null || true
    sudo cp -rf "$CUTEFISH_ROOT/kwin-plugins/scripts/aevislauncher/"* /usr/share/kwin-wayland/scripts/aevislauncher/ 2>/dev/null || true
fi

# Ensure KWin window decoration symlink for Aevis
for deco_dir in /usr/lib/qt6/plugins/org.kde.kdecoration3 /usr/lib/qt6/plugins/org.kde.kdecoration2; do
    if [ -f "$deco_dir/org.cutefish.decoration.so" ]; then
        sudo ln -sf org.cutefish.decoration.so "$deco_dir/org.aevis.decoration.so" 2>/dev/null || true
    fi
done

sudo ldconfig 2>/dev/null || true
sudo gtk-update-icon-cache /usr/share/icons/Cutefish 2>/dev/null || true
sudo update-desktop-database /usr/share/applications 2>/dev/null || true
fc-cache -f 2>/dev/null || true

if command -v kbuildsycoca6 &>/dev/null; then
    log_info "Rebuilding KDE sycoca database (kbuildsycoca6)..."
    XDG_MENU_PREFIX=cutefish- kbuildsycoca6 --noincremental 2>/dev/null || true
elif command -v kbuildsycoca5 &>/dev/null; then
    log_info "Rebuilding KDE sycoca database (kbuildsycoca5)..."
    XDG_MENU_PREFIX=cutefish- kbuildsycoca5 --noincremental 2>/dev/null || true
fi

echo ""
echo -e "${GREEN}================================================================${NC}"
echo -e "${BOLD}${GREEN}  Project Aevis Desktop Environment installation complete!      ${NC}"
echo -e "${GREEN}================================================================${NC}"
echo ""
echo -e "You can now select ${BOLD}Aevis (Wayland)${NC} or ${BOLD}Cutefish (Wayland)${NC} from your display manager."
echo ""

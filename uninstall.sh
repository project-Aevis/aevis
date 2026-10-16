#!/usr/bin/env bash
#
# Project Aevis / Cutefish OS Desktop Environment - Uninstaller
# Completely removes all installed DE binaries, libraries, desktop sessions,
# application files, plugins, icons, and themes from the system.
#
set -euo pipefail

# ANSI color codes
BOLD="\033[1m"
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
CYAN="\033[1;36m"
RED="\033[1;31m"
MAGENTA="\033[1;35m"
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

log_step() {
    echo -e "\n${MAGENTA}================================================================${NC}"
    echo -e "${BOLD}${MAGENTA}  $1${NC}"
    echo -e "${MAGENTA}================================================================${NC}\n"
}

AEVIS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_PREFIX="/usr"
PURGE_CONFIGS=false
CLEAN_BUILD=false
DRY_RUN=false
SKIP_SUDO=false

show_help() {
    cat << EOF
Project Aevis / Cutefish OS Desktop Environment - Uninstaller

Usage:
  ./uninstall.sh [OPTIONS]

Options:
  -h, --help            Show this help message and exit
  --prefix <PATH>       Installation prefix to clean (default: /usr)
  --purge-configs       Also remove user and system configuration files
                        (~/.config/aevis, ~/.config/cutefishos, /etc/aevis*, /etc/cutefish*)
  --clean-build         Also delete all build/ directories within the repository
  --dry-run             Simulate removal without actually deleting any files
  --no-sudo             Skip sudo calls (use if already running as root)

Description:
  This script safely and completely uninstalls all Project Aevis and Cutefish OS
  components from your system, including binaries, libraries, desktop sessions,
  icons, wallpapers, SDDM themes, KWin plugins, and Qt platform plugins.
EOF
    exit 0
}

# Parse command line options
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            show_help
            ;;
        --prefix)
            INSTALL_PREFIX="$2"
            shift 2
            ;;
        --purge-configs)
            PURGE_CONFIGS=true
            shift
            ;;
        --clean-build)
            CLEAN_BUILD=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --no-sudo)
            SKIP_SUDO=true
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            ;;
    esac
done

# Sudo wrapper
SUDO_CMD=""
if [ "$SKIP_SUDO" = false ] && [ "$EUID" -ne 0 ]; then
    SUDO_CMD="sudo"
fi

cleanup() {
    if [ -n "${SUDO_PID:-}" ]; then
        kill "$SUDO_PID" 2>/dev/null || true
    fi
}
trap cleanup EXIT

if [ -n "$SUDO_CMD" ] && [ "$DRY_RUN" = false ]; then
    log_info "Acquiring root privileges for uninstallation..."
    sudo -v
    while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
    SUDO_PID=$!
fi

remove_file() {
    local target="$1"
    if [ -e "$target" ] || [ -L "$target" ]; then
        if [ "$DRY_RUN" = true ]; then
            echo -e "${YELLOW}[DRY-RUN]${NC} Would remove file: $target"
        else
            $SUDO_CMD rm -f "$target" 2>/dev/null || true
            echo -e "${GREEN}[REMOVED]${NC} $target"
        fi
    fi
}

remove_dir() {
    local target="$1"
    if [ -d "$target" ]; then
        if [ "$DRY_RUN" = true ]; then
            echo -e "${YELLOW}[DRY-RUN]${NC} Would remove directory: $target"
        else
            $SUDO_CMD rm -rf "$target" 2>/dev/null || true
            echo -e "${GREEN}[REMOVED]${NC} $target (directory)"
        fi
    fi
}

remove_empty_dir() {
    local target="$1"
    if [ -d "$target" ]; then
        if [ "$DRY_RUN" = false ]; then
            $SUDO_CMD rmdir -p --ignore-fail-on-non-empty "$target" 2>/dev/null || true
        fi
    fi
}

# ==============================================================================
# Step 1: Remove Files Recorded in CMake Install Manifests
# ==============================================================================
log_step "Step 1: Removing files tracked by CMake install manifests"

manifest_count=0
while IFS= read -r manifest; do
    if [ -f "$manifest" ]; then
        manifest_count=$((manifest_count + 1))
        rel_manifest="${manifest#"$AEVIS_ROOT"/}"
        log_info "Processing manifest: $rel_manifest"
        while IFS= read -r file_path || [ -n "$file_path" ]; do
            # Skip empty lines or comments
            [ -z "$file_path" ] && continue
            [[ "$file_path" =~ ^# ]] && continue

            # If user specified a non-standard prefix, adjust path
            if [ "$INSTALL_PREFIX" != "/usr" ]; then
                file_path="${file_path/#\/usr/"$INSTALL_PREFIX"}"
            fi

            remove_file "$file_path"
        done < "$manifest"
    fi
done < <(find "$AEVIS_ROOT" -name "install_manifest.txt" 2>/dev/null)

log_success "Processed $manifest_count CMake install manifests."

# ==============================================================================
# Step 2: Remove All Aevis and Cutefish Binaries & Symlinks
# ==============================================================================
log_step "Step 2: Removing binaries and symlinks from $INSTALL_PREFIX/bin"

for bin in \
    cutefish-shell aevis-shell \
    cutefish-session aevis-session \
    cutefish-services aevis-services \
    cutefish-appruntime aevis-appruntime \
    cutefish-statusbar aevis-statusbar \
    cutefish-dock aevis-dock \
    cutefish-launcher aevis-launcher \
    cutefish-settings aevis-settings \
    cutefish-filemanager aevis-filemanager \
    cutefish-terminal aevis-terminal \
    cutefish-calculator aevis-calculator \
    cutefish-screenshot aevis-screenshot \
    cutefish-screenlocker aevis-screenlocker \
    cutefish-taskmanager aevis-taskmanager aevis-task-manager \
    cutefish-photos aevis-photos \
    cutefish-updator aevis-updator \
    cutefish-polkit-agent aevis-polkit-agent \
    cutefish-screen-brightness aevis-screen-brightness \
    cutefish-cpufreq aevis-cpufreq \
    cutefish-sddm-helper aevis-sddm-helper \
    cutefish-wayland-session aevis-wayland-session \
    cutefish-kwin-wayland-session aevis-kwin-wayland-session
do
    remove_file "$INSTALL_PREFIX/bin/$bin"
    remove_file "/usr/local/bin/$bin"
    remove_file "$HOME/.local/bin/$bin"
done

# ==============================================================================
# Step 3: Remove Wayland Sessions & Menu Definitions
# ==============================================================================
log_step "Step 3: Removing Wayland session and menu entries"

# Wayland sessions
remove_file "$INSTALL_PREFIX/share/wayland-sessions/cutefish-wayland.desktop"
remove_file "$INSTALL_PREFIX/share/wayland-sessions/aevis-wayland.desktop"
remove_file "/usr/share/wayland-sessions/cutefish-wayland.desktop"
remove_file "/usr/share/wayland-sessions/aevis-wayland.desktop"

# XDG Menus
remove_file "/etc/xdg/menus/cutefish-applications.menu"
remove_file "/etc/xdg/menus/aevis-applications.menu"

# Dock lists
remove_file "/etc/cutefish-dock-list.conf"
remove_file "/etc/aevis-dock-list.conf"

# Environment scripts
remove_file "/etc/profile.d/cutefish-wayland.sh"
remove_file "/etc/profile.d/aevis-wayland.sh"
remove_file "/usr/lib/environment.d/10-cutefish.conf"
remove_file "/usr/lib/environment.d/10-aevis.conf"
remove_file "/etc/environment.d/10-cutefish.conf"
remove_file "/etc/environment.d/10-aevis.conf"

# Fontconfig overrides
remove_file "/etc/fonts/conf.d/99-cutefish.conf"
remove_file "/etc/fonts/conf.d/99-aevis.conf"
remove_file "$HOME/.config/fontconfig/conf.d/99-cutefish.conf"
remove_file "$HOME/.config/fontconfig/conf.d/99-aevis.conf"

# ==============================================================================
# Step 4: Remove Application Desktop Files & Autostart Entries
# ==============================================================================
log_step "Step 4: Removing desktop entries and autostart launchers"

for app in \
    calculator filemanager photos screenshot settings shell taskmanager terminal updator polkit-agent
do
    remove_file "$INSTALL_PREFIX/share/applications/cutefish-$app.desktop"
    remove_file "$INSTALL_PREFIX/share/applications/aevis-$app.desktop"
    remove_file "/usr/share/applications/cutefish-$app.desktop"
    remove_file "/usr/share/applications/aevis-$app.desktop"
    remove_file "/etc/xdg/autostart/cutefish-$app.desktop"
    remove_file "/etc/xdg/autostart/aevis-$app.desktop"
done

# ==============================================================================
# Step 5: Remove Themes, Wallpapers, SDDM & Plymouth Assets
# ==============================================================================
log_step "Step 5: Removing themes, wallpapers, and display manager assets"

# Wallpapers
remove_dir "$INSTALL_PREFIX/share/backgrounds/cutefishos"
remove_dir "$INSTALL_PREFIX/share/backgrounds/aevis"
remove_dir "/usr/share/backgrounds/cutefishos"
remove_dir "/usr/share/backgrounds/aevis"

# SDDM Themes
remove_dir "$INSTALL_PREFIX/share/sddm/themes/cutefish"
remove_dir "$INSTALL_PREFIX/share/sddm/themes/aevis"
remove_dir "/usr/share/sddm/themes/cutefish"
remove_dir "/usr/share/sddm/themes/aevis"

# Plymouth Themes
remove_dir "$INSTALL_PREFIX/share/plymouth/themes/cutefish-logo"
remove_dir "$INSTALL_PREFIX/share/plymouth/themes/cutefish-text"
remove_dir "$INSTALL_PREFIX/share/plymouth/themes/aevis-logo"
remove_dir "$INSTALL_PREFIX/share/plymouth/themes/aevis-text"
remove_dir "/usr/share/plymouth/themes/cutefish-logo"
remove_dir "/usr/share/plymouth/themes/cutefish-text"
remove_dir "/usr/share/plymouth/themes/aevis-logo"
remove_dir "/usr/share/plymouth/themes/aevis-text"

# Cursor & GTK Themes
remove_dir "$INSTALL_PREFIX/share/icons/Cutefish"
remove_dir "$INSTALL_PREFIX/share/icons/cutefish-dark"
remove_dir "$INSTALL_PREFIX/share/icons/cutefish-light"
remove_dir "$INSTALL_PREFIX/share/icons/aevis-dark"
remove_dir "$INSTALL_PREFIX/share/icons/aevis-light"
remove_dir "$INSTALL_PREFIX/share/themes/cutefish-dark"
remove_dir "$INSTALL_PREFIX/share/themes/cutefish-light"
remove_dir "$INSTALL_PREFIX/share/themes/aevis-dark"
remove_dir "$INSTALL_PREFIX/share/themes/aevis-light"

# KWin plugins & scripts
remove_dir "$INSTALL_PREFIX/share/kwin/scripts/cutefishlauncher"
remove_dir "$INSTALL_PREFIX/share/kwin/scripts/cutefish_popups"
remove_dir "$INSTALL_PREFIX/share/kwin/scripts/cutefish_scale"
remove_dir "$INSTALL_PREFIX/share/kwin/scripts/aevislauncher"
remove_file "$INSTALL_PREFIX/lib/qt6/plugins/org.kde.kdecoration2/cutefishdecoration.so"
remove_file "$INSTALL_PREFIX/lib64/qt6/plugins/org.kde.kdecoration2/cutefishdecoration.so"
remove_file "$INSTALL_PREFIX/lib/qt6/plugins/kwin/effects/plugins/libcutefish_roundedwindow.so"
remove_file "$INSTALL_PREFIX/lib64/qt6/plugins/kwin/effects/plugins/libcutefish_roundedwindow.so"

# Qt Plugins and QML modules
for lib_dir in "$INSTALL_PREFIX/lib" "$INSTALL_PREFIX/lib64" "/usr/lib" "/usr/lib64"; do
    remove_file "$lib_dir/qt6/plugins/styles/libcutefishstyle.so"
    remove_file "$lib_dir/qt6/plugins/platformthemes/libcutefishplatformtheme.so"
    remove_file "$lib_dir/qt6/plugins/imageformats/libqsvg-rsvg.so"
    remove_dir "$lib_dir/qt6/qml/Cutefish"
    remove_dir "$lib_dir/qt6/qml/FishUI"
    remove_dir "$lib_dir/qt6/qml/Aevis"
done

# Headers and shared data
remove_dir "$INSTALL_PREFIX/include/Cutefish"
remove_dir "$INSTALL_PREFIX/include/FishUI"
remove_dir "$INSTALL_PREFIX/include/Aevis"

for app in \
    cutefish-shell cutefish-statusbar cutefish-dock cutefish-launcher \
    cutefish-filemanager cutefish-terminal cutefish-calculator cutefish-screenshot \
    cutefish-screenlocker cutefish-taskmanager cutefish-photos cutefish-updator \
    cutefish-polkit-agent cutefish-settings cutefish-services \
    aevis-shell aevis-statusbar aevis-dock aevis-launcher \
    aevis-filemanager aevis-terminal aevis-calculator aevis-screenshot \
    aevis-screenlocker aevis-taskmanager aevis-photos aevis-updator \
    aevis-polkit-agent aevis-settings aevis-services
do
    remove_dir "$INSTALL_PREFIX/share/$app"
    remove_dir "/usr/share/$app"
done

# ==============================================================================
# Step 6: User Configuration Files (Optional: --purge-configs)
# ==============================================================================
if [ "$PURGE_CONFIGS" = true ]; then
    log_step "Step 6: Purging user configurations and system configs"

    remove_dir "$HOME/.config/aevis"
    remove_dir "$HOME/.config/cutefishos"
    remove_dir "$HOME/.cache/aevis"
    remove_dir "$HOME/.cache/cutefish"
    remove_dir "$HOME/.cache/cutefishos"
    remove_file "$HOME/.config/cutefish-dock-list.conf"
    remove_file "$HOME/.config/aevis-dock-list.conf"

    remove_file "/etc/aevis"
    remove_file "/etc/cutefish"
    remove_dir "/etc/aevis"
    remove_dir "/etc/cutefish"
else
    log_info "Step 6: Preserving user configurations in ~/.config/aevis and ~/.config/cutefishos (pass --purge-configs to remove them)."
fi

# ==============================================================================
# Step 7: Clean Repository Build Directories (Optional: --clean-build)
# ==============================================================================
if [ "$CLEAN_BUILD" = true ]; then
    log_step "Step 7: Cleaning all build directories in repository"

    while IFS= read -r bdir; do
        if [ -d "$bdir" ]; then
            remove_dir "$bdir"
        fi
    done < <(find "$AEVIS_ROOT" -mindepth 2 -maxdepth 3 -type d -name "build" 2>/dev/null)
    log_success "Workspace build directories removed."
fi

# ==============================================================================
# Step 8: Refresh System Linker, Font & Icon Databases
# ==============================================================================
log_step "Step 8: Refreshing system caches"

if [ "$DRY_RUN" = false ]; then
    log_info "Updating dynamic linker run-time bindings (ldconfig)..."
    $SUDO_CMD ldconfig 2>/dev/null || true

    log_info "Updating desktop and MIME application database..."
    $SUDO_CMD update-desktop-database "$INSTALL_PREFIX/share/applications" 2>/dev/null || true
    $SUDO_CMD update-desktop-database "/usr/share/applications" 2>/dev/null || true

    log_info "Updating icon cache..."
    $SUDO_CMD gtk-update-icon-cache -f "$INSTALL_PREFIX/share/icons/hicolor" 2>/dev/null || true
    $SUDO_CMD gtk-update-icon-cache -f "/usr/share/icons/hicolor" 2>/dev/null || true

    log_info "Updating fontconfig cache..."
    fc-cache -f 2>/dev/null || true

    if command -v kbuildsycoca6 &>/dev/null; then
        log_info "Rebuilding KDE sycoca database (kbuildsycoca6)..."
        kbuildsycoca6 --noincremental 2>/dev/null || true
    elif command -v kbuildsycoca5 &>/dev/null; then
        log_info "Rebuilding KDE sycoca database (kbuildsycoca5)..."
        kbuildsycoca5 --noincremental 2>/dev/null || true
    fi

    if command -v glib-compile-schemas &>/dev/null && [ -d "$INSTALL_PREFIX/share/glib-2.0/schemas" ]; then
        $SUDO_CMD glib-compile-schemas "$INSTALL_PREFIX/share/glib-2.0/schemas" 2>/dev/null || true
    fi
fi

echo ""
echo -e "${GREEN}================================================================${NC}"
echo -e "${BOLD}${GREEN}  Project Aevis / Cutefish OS uninstallation completed!         ${NC}"
echo -e "${GREEN}================================================================${NC}"
echo ""

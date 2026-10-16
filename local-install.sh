#!/usr/bin/env bash
#
# Project Aevis Desktop Environment - Local Offline Build & Installer
# Built upon the foundation of Cutefish OS.
# Builds and installs all Project Aevis DE components locally from this workspace without git cloning or network access.
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

CUTEFISH_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_PREFIX="/usr"
CLEAN_BUILD=false
DRY_RUN=false
SKIP_SUDO=false
MODE="all" # all, core, apps, themes

show_help() {
    cat << EOF
Cutefish Desktop Environment - Local Installer

Usage:
  ./local-install.sh [OPTIONS]

Options:
  -h, --help            Show this help message and exit
  --clean               Remove existing build/ directories before building
  --prefix <PATH>       Installation prefix (default: /usr)
  --no-sudo             Skip sudo calls (use if already root or in container)
  --core-only           Build and install only core DE components and frameworks
  --apps-only           Build and install only Cutefish applications (terminal, calculator, screenshot, music)
  --themes-only         Install only themes, icons, wallpapers, SDDM and cursor assets
  --dry-run             Simulate build and install steps without executing them

Description:
  This script performs a completely offline, local build and installation of the
  Cutefish Desktop Environment from the current repository workspace.
  It does not execute git clone, git pull, or require internet connectivity.

EOF
    exit 0
}

# Parse command line options
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            show_help
            ;;
        --clean)
            CLEAN_BUILD=true
            shift
            ;;
        --prefix)
            INSTALL_PREFIX="$2"
            shift 2
            ;;
        --no-sudo)
            SKIP_SUDO=true
            shift
            ;;
        --core-only)
            MODE="core"
            shift
            ;;
        --apps-only)
            MODE="apps"
            shift
            ;;
        --themes-only)
            MODE="themes"
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Run './local-install.sh --help' for usage."
            exit 1
            ;;
    esac
done

SUDO_CMD="sudo"
if [ "$SKIP_SUDO" = true ] || [ "$EUID" -eq 0 ]; then
    SUDO_CMD=""
fi

# Dynamic Qt 6 toolchain path discovery
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

log_info "Workspace root: $CUTEFISH_ROOT"
log_info "Target prefix:  $INSTALL_PREFIX"
log_info "Build mode:     $MODE"
log_info "Parallel jobs:  $(nproc)"

cleanup() {
    if [ -n "${SUDO_PID:-}" ]; then
        kill "$SUDO_PID" 2>/dev/null || true
    fi
    if [ "$EUID" -eq 0 ] && [ -n "${SUDO_USER:-}" ] && [ "$DRY_RUN" = false ]; then
        chown -R "$(id -u "$SUDO_USER")":"$(id -g "$SUDO_USER")" "$CUTEFISH_ROOT" 2>/dev/null || true
    fi
}
trap cleanup EXIT

# Acquire root credentials if necessary
if [ -n "$SUDO_CMD" ] && [ "$DRY_RUN" = false ]; then
    log_info "Acquiring root privileges for installation..."
    sudo -v
    while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
    SUDO_PID=$!

    # Fix any files/directories in workspace that may have been created with root ownership in previous runs
    if [ -n "$(find "$CUTEFISH_ROOT" -maxdepth 3 -user root -print -quit 2>/dev/null)" ]; then
        log_info "Ensuring workspace build directories are owned by $(id -un)..."
        $SUDO_CMD chown -R "$(id -u):$(id -g)" "$CUTEFISH_ROOT" 2>/dev/null || true
        $SUDO_CMD rm -rf "$CUTEFISH_ROOT/gtk-themes/build.root.bak" "$CUTEFISH_ROOT/updator/build.root.bak" 2>/dev/null || true
    fi
fi

# ==============================================================================
# Build & Install Helper Function
# ==============================================================================
build_and_install_component() {
    local name="$1"
    local dir="$CUTEFISH_ROOT/$name"
    local extra_args="${2:-}"

    if [ ! -d "$dir" ]; then
        log_warn "Component directory '$name' does not exist in local workspace, skipping."
        return 0
    fi

    if [ ! -f "$dir/CMakeLists.txt" ]; then
        log_warn "No CMakeLists.txt found in '$name', skipping CMake build."
        return 0
    fi

    log_info "Configuring and compiling local component: $name..."

    if [ "$CLEAN_BUILD" = true ] && [ -d "$dir/build" ]; then
        log_info "Cleaning previous build tree for $name..."
        if [ "$DRY_RUN" = false ]; then
            if [ -n "$SUDO_CMD" ]; then
                $SUDO_CMD rm -rf "$dir/build"
            else
                rm -rf "$dir/build"
            fi
        fi
    fi

    if [ "$DRY_RUN" = true ]; then
        echo -e "${YELLOW}[DRY-RUN]${NC} cmake -B $dir/build -S $dir -DCMAKE_INSTALL_PREFIX=$INSTALL_PREFIX -DCMAKE_BUILD_TYPE=Release"
        echo -e "${YELLOW}[DRY-RUN]${NC} cmake --build $dir/build -j$(nproc)"
        echo -e "${YELLOW}[DRY-RUN]${NC} $SUDO_CMD cmake --install $dir/build"
        return 0
    fi

    # Ensure build directory is writable by current user
    if [ -d "$dir/build" ] && [ ! -w "$dir/build" ] && [ -n "$SUDO_CMD" ]; then
        log_warn "Fixing permissions on non-writable build directory for $name..."
        $SUDO_CMD chown -R "$(id -u):$(id -g)" "$dir/build" 2>/dev/null || true
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
        -DCMAKE_INSTALL_PREFIX="$INSTALL_PREFIX" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_CXX_FLAGS_RELEASE="-O3 -DNDEBUG -ffunction-sections -fdata-sections" \
        -DCMAKE_SHARED_LINKER_FLAGS_RELEASE="-Wl,--gc-sections -Wl,--as-needed" \
        -DCMAKE_EXE_LINKER_FLAGS_RELEASE="-Wl,--gc-sections -Wl,--as-needed" \
        $extra_args

    cmake --build "$dir/build" -j"$(nproc)"

    if [ -n "$SUDO_CMD" ]; then
        $SUDO_CMD cmake --install "$dir/build"
        # Restore ownership in case cmake --install wrote install_manifest.txt as root
        $SUDO_CMD chown -R "$(id -u):$(id -g)" "$dir/build" 2>/dev/null || true
    else
        cmake --install "$dir/build"
    fi

    log_success "$name compiled and installed successfully."
}

# ==============================================================================
# Step 1: Core Frameworks and Desktop Environment Components
# ==============================================================================
if [ "$MODE" = "all" ] || [ "$MODE" = "core" ]; then
    log_step "Step 1: Building Core Frameworks & Desktop Environment Components"

    # Topological order of dependencies
    build_and_install_component "fishui"
    build_and_install_component "cutefish-framework"
    build_and_install_component "core"
    build_and_install_component "kwin-plugins"
    build_and_install_component "dock"
    build_and_install_component "launcher"
    build_and_install_component "statusbar"
    build_and_install_component "shell"
    build_and_install_component "settings"
    build_and_install_component "screenlocker"
    build_and_install_component "qt-plugins"
fi

# ==============================================================================
# Step 2: Cutefish Applications
# ==============================================================================
if [ "$MODE" = "all" ] || [ "$MODE" = "apps" ]; then
    log_step "Step 2: Building Cutefish Applications"

    build_and_install_component "filemanager"
    build_and_install_component "terminal"
    build_and_install_component "calculator"
    build_and_install_component "screenshot"
    build_and_install_component "photos"
    build_and_install_component "music"
    build_and_install_component "task-manager"

    if [ -d "$CUTEFISH_ROOT/updator" ]; then
        build_and_install_component "updator" || log_warn "Optional component cutefish-updator skipped or build failed."
    fi
fi

# ==============================================================================
# Step 3: Desktop Assets, Themes & Wallpapers
# ==============================================================================
if [ "$MODE" = "all" ] || [ "$MODE" = "themes" ]; then
    log_step "Step 3: Installing Themes, Icons, Wallpapers, and Assets"

    # Clean up any misplaced cursor themes in themes directory before installing GTK themes
    if [ "$DRY_RUN" = false ]; then
        if [ -f "$INSTALL_PREFIX/share/themes/aevis-dark/cursor.theme" ] || [ -f "/usr/share/themes/aevis-dark/cursor.theme" ]; then
            log_info "Removing misplaced cursor themes from themes directory..."
            $SUDO_CMD rm -rf "$INSTALL_PREFIX/share/themes/aevis-dark" "$INSTALL_PREFIX/share/themes/aevis-light" \
                             "$INSTALL_PREFIX/share/themes/cutefish-dark" "$INSTALL_PREFIX/share/themes/cutefish-light" \
                             /usr/share/themes/aevis-dark /usr/share/themes/aevis-light \
                             /usr/share/themes/cutefish-dark /usr/share/themes/cutefish-light 2>/dev/null || true
        fi
    fi

    build_and_install_component "icons"
    build_and_install_component "wallpapers"
    build_and_install_component "gtk-themes"

    # Ensure user local themes directories have the GTK themes
    if [ "$DRY_RUN" = false ] && [ -n "$HOME" ] && [ -d "$CUTEFISH_ROOT/gtk-themes" ]; then
        log_info "Ensuring GTK themes are linked to user theme directories..."
        mkdir -p "$HOME/.local/share/themes" "$HOME/.themes"
        rm -rf "$HOME/.local/share/themes/.git" "$HOME/.themes/.git" "$HOME/.local/share/themes/CMakeLists.txt" "$HOME/.themes/CMakeLists.txt" 2>/dev/null || true
        for t in Aevis Aevis-light Aevis-dark Cutefish Cutefish-light Cutefish-dark aevis aevis-light aevis-dark cutefish cutefish-light cutefish-dark; do
            if [ -d "$INSTALL_PREFIX/share/themes/$t" ]; then
                rm -rf "$HOME/.local/share/themes/$t" "$HOME/.themes/$t" 2>/dev/null || true
                ln -sf "$INSTALL_PREFIX/share/themes/$t" "$HOME/.local/share/themes/$t"
                ln -sf "$INSTALL_PREFIX/share/themes/$t" "$HOME/.themes/$t"
            fi
        done
    fi

    # SDDM Theme Installation
    if [ -d "$CUTEFISH_ROOT/sddm-theme" ]; then
        log_info "Installing SDDM theme files..."
        if [ "$DRY_RUN" = false ]; then
            $SUDO_CMD mkdir -p "$INSTALL_PREFIX/share/sddm/themes/cutefish" "$INSTALL_PREFIX/share/sddm/themes/aevis"
            $SUDO_CMD cp -f "$CUTEFISH_ROOT/sddm-theme/"*.qml \
                           "$CUTEFISH_ROOT/sddm-theme/"*.svg \
                           "$CUTEFISH_ROOT/sddm-theme/"*.desktop \
                           "$CUTEFISH_ROOT/sddm-theme/theme.conf" \
                           "$INSTALL_PREFIX/share/sddm/themes/cutefish/" 2>/dev/null || true
            $SUDO_CMD cp -f "$CUTEFISH_ROOT/sddm-theme/"*.qml \
                           "$CUTEFISH_ROOT/sddm-theme/"*.svg \
                           "$CUTEFISH_ROOT/sddm-theme/"*.desktop \
                           "$CUTEFISH_ROOT/sddm-theme/theme.conf" \
                           "$INSTALL_PREFIX/share/sddm/themes/aevis/" 2>/dev/null || true
            $SUDO_CMD mkdir -p "$INSTALL_PREFIX/share/sddm/themes/cutefish/faces" "$INSTALL_PREFIX/share/sddm/themes/aevis/faces"
            $SUDO_CMD cp -rf "$CUTEFISH_ROOT/sddm-theme/faces/"* "$INSTALL_PREFIX/share/sddm/themes/cutefish/faces/" 2>/dev/null || true
            $SUDO_CMD cp -rf "$CUTEFISH_ROOT/sddm-theme/faces/"* "$INSTALL_PREFIX/share/sddm/themes/aevis/faces/" 2>/dev/null || true
            $SUDO_CMD mkdir -p /etc/sddm.conf.d
            $SUDO_CMD cp -f "$CUTEFISH_ROOT/sddm-theme/sddm.conf" /etc/sddm.conf.d/theme.conf 2>/dev/null || true
            $SUDO_CMD cp -f "$CUTEFISH_ROOT/sddm-theme/sddm.conf" /etc/sddm.conf 2>/dev/null || true
        fi
        log_success "SDDM theme installed."
    fi

    # Cursor Themes Installation
    if [ -d "$CUTEFISH_ROOT/cursor-themes" ]; then
        log_info "Installing cursor themes..."
        if [ "$DRY_RUN" = false ]; then
            $SUDO_CMD mkdir -p "$INSTALL_PREFIX/share/icons"
            [ -d "$CUTEFISH_ROOT/cursor-themes/cutefish-dark" ] && $SUDO_CMD cp -r "$CUTEFISH_ROOT/cursor-themes/cutefish-dark" "$INSTALL_PREFIX/share/icons/"
            [ -d "$CUTEFISH_ROOT/cursor-themes/cutefish-light" ] && $SUDO_CMD cp -r "$CUTEFISH_ROOT/cursor-themes/cutefish-light" "$INSTALL_PREFIX/share/icons/"
            [ -d "$CUTEFISH_ROOT/cursor-themes/cutefish-dark" ] && $SUDO_CMD cp -r "$CUTEFISH_ROOT/cursor-themes/cutefish-dark" "$INSTALL_PREFIX/share/icons/aevis-dark"
            [ -d "$CUTEFISH_ROOT/cursor-themes/cutefish-light" ] && $SUDO_CMD cp -r "$CUTEFISH_ROOT/cursor-themes/cutefish-light" "$INSTALL_PREFIX/share/icons/aevis-light"
        fi
        log_success "Cursor themes installed."
    fi

    # Plymouth Theme Installation
    if [ -d "$CUTEFISH_ROOT/plymouth-theme" ]; then
        log_info "Installing plymouth themes..."
        if [ "$DRY_RUN" = false ]; then
            $SUDO_CMD mkdir -p "$INSTALL_PREFIX/share/plymouth/themes"
            [ -d "$CUTEFISH_ROOT/plymouth-theme/cutefish-logo" ] && $SUDO_CMD cp -r "$CUTEFISH_ROOT/plymouth-theme/cutefish-logo" "$INSTALL_PREFIX/share/plymouth/themes/" && $SUDO_CMD cp -r "$CUTEFISH_ROOT/plymouth-theme/cutefish-logo" "$INSTALL_PREFIX/share/plymouth/themes/aevis-logo"
            [ -d "$CUTEFISH_ROOT/plymouth-theme/cutefish-text" ] && $SUDO_CMD cp -r "$CUTEFISH_ROOT/plymouth-theme/cutefish-text" "$INSTALL_PREFIX/share/plymouth/themes/" && $SUDO_CMD cp -r "$CUTEFISH_ROOT/plymouth-theme/cutefish-text" "$INSTALL_PREFIX/share/plymouth/themes/aevis-text"
        fi
        log_success "Plymouth themes installed."
    fi
fi

# ==============================================================================
# Step 4: Desktop Session Registration & Post-Install Integration
# ==============================================================================
if [ "$MODE" = "all" ] || [ "$MODE" = "core" ]; then
    log_step "Step 4: Registering Desktop Session & Refreshing System Caches"

    if [ "$DRY_RUN" = false ]; then
        # Ensure Wayland session desktop entry exists for display managers
        $SUDO_CMD mkdir -p "$INSTALL_PREFIX/share/wayland-sessions"
        if [ -f "$CUTEFISH_ROOT/core/session/cutefish-wayland.desktop" ]; then
            $SUDO_CMD cp -f "$CUTEFISH_ROOT/core/session/cutefish-wayland.desktop" "$INSTALL_PREFIX/share/wayland-sessions/"
        fi
        if [ -f "$CUTEFISH_ROOT/core/session/aevis-wayland.desktop" ]; then
            $SUDO_CMD cp -f "$CUTEFISH_ROOT/core/session/aevis-wayland.desktop" "$INSTALL_PREFIX/share/wayland-sessions/"
        fi

        # Ensure session entry scripts are installed and executable
        $SUDO_CMD mkdir -p "$INSTALL_PREFIX/bin"
        if [ -f "$CUTEFISH_ROOT/core/session/cutefish-wayland-session" ]; then
            $SUDO_CMD cp -f "$CUTEFISH_ROOT/core/session/cutefish-wayland-session" "$INSTALL_PREFIX/bin/"
            $SUDO_CMD chmod +x "$INSTALL_PREFIX/bin/cutefish-wayland-session"
        fi
        if [ -f "$CUTEFISH_ROOT/core/session/aevis-wayland-session" ]; then
            $SUDO_CMD cp -f "$CUTEFISH_ROOT/core/session/aevis-wayland-session" "$INSTALL_PREFIX/bin/"
            $SUDO_CMD chmod +x "$INSTALL_PREFIX/bin/aevis-wayland-session"
        fi
        if [ -f "$CUTEFISH_ROOT/core/session/cutefish-kwin-wayland-session" ]; then
            $SUDO_CMD cp -f "$CUTEFISH_ROOT/core/session/cutefish-kwin-wayland-session" "$INSTALL_PREFIX/bin/"
            $SUDO_CMD chmod +x "$INSTALL_PREFIX/bin/cutefish-kwin-wayland-session"
        fi
        if [ -f "$CUTEFISH_ROOT/core/session/aevis-kwin-wayland-session" ]; then
            $SUDO_CMD cp -f "$CUTEFISH_ROOT/core/session/aevis-kwin-wayland-session" "$INSTALL_PREFIX/bin/"
            $SUDO_CMD chmod +x "$INSTALL_PREFIX/bin/aevis-kwin-wayland-session"
        fi

        # Install binary aliases for Aevis commands
        for app in session shell filemanager terminal settings calculator taskmanager photos screenshot screenlocker launcher dock statusbar services appruntime polkit-agent; do
            cf_bin="cutefish-$app"
            av_bin="aevis-$app"
            if [ -f "$INSTALL_PREFIX/bin/$cf_bin" ]; then
                $SUDO_CMD ln -sf "$cf_bin" "$INSTALL_PREFIX/bin/$av_bin"
            fi
        done
        [ -f "$INSTALL_PREFIX/bin/cutefish-taskmanager" ] && $SUDO_CMD ln -sf cutefish-taskmanager "$INSTALL_PREFIX/bin/aevis-taskmanager"
        [ -f "$INSTALL_PREFIX/bin/cutefish-taskmanager" ] && $SUDO_CMD ln -sf cutefish-taskmanager "$INSTALL_PREFIX/bin/aevis-task-manager"

        # Ensure Cutefish and Aevis applications menu definitions are installed
        $SUDO_CMD mkdir -p /etc/xdg/menus
        if [ -f "$CUTEFISH_ROOT/core/session/cutefish-applications.menu" ]; then
            $SUDO_CMD cp -f "$CUTEFISH_ROOT/core/session/cutefish-applications.menu" /etc/xdg/menus/
            $SUDO_CMD cp -f "$CUTEFISH_ROOT/core/session/cutefish-applications.menu" /etc/xdg/menus/aevis-applications.menu
        fi

        # Ensure cutefish-shell and aevis-shell desktop files with Wayland permissions are installed
        $SUDO_CMD mkdir -p "$INSTALL_PREFIX/share/applications"
        if [ -f "$CUTEFISH_ROOT/shell/build/cutefish-shell.desktop" ]; then
            $SUDO_CMD cp -f "$CUTEFISH_ROOT/shell/build/cutefish-shell.desktop" "$INSTALL_PREFIX/share/applications/"
        fi
        if [ -f "$CUTEFISH_ROOT/shell/build/aevis-shell.desktop" ]; then
            $SUDO_CMD cp -f "$CUTEFISH_ROOT/shell/build/aevis-shell.desktop" "$INSTALL_PREFIX/share/applications/"
        elif [ -f "$CUTEFISH_ROOT/shell/build/cutefish-shell.desktop" ]; then
            $SUDO_CMD cp -f "$CUTEFISH_ROOT/shell/build/cutefish-shell.desktop" "$INSTALL_PREFIX/share/applications/aevis-shell.desktop"
        fi

        # Ensure KWin scripts and effects are installed to system directories
        $SUDO_CMD mkdir -p "$INSTALL_PREFIX/share/kwin/scripts/cutefishlauncher" \
                           "$INSTALL_PREFIX/share/kwin/scripts/aevislauncher" \
                           "$INSTALL_PREFIX/share/kwin-wayland/scripts/cutefishlauncher" \
                           "$INSTALL_PREFIX/share/kwin-wayland/scripts/aevislauncher"
        if [ -d "$CUTEFISH_ROOT/kwin-plugins/scripts/cutefishlauncher" ]; then
            $SUDO_CMD cp -rf "$CUTEFISH_ROOT/kwin-plugins/scripts/cutefishlauncher/"* "$INSTALL_PREFIX/share/kwin/scripts/cutefishlauncher/" 2>/dev/null || true
            $SUDO_CMD cp -rf "$CUTEFISH_ROOT/kwin-plugins/scripts/cutefishlauncher/"* "$INSTALL_PREFIX/share/kwin-wayland/scripts/cutefishlauncher/" 2>/dev/null || true
        fi
        if [ -d "$CUTEFISH_ROOT/kwin-plugins/scripts/aevislauncher" ]; then
            $SUDO_CMD cp -rf "$CUTEFISH_ROOT/kwin-plugins/scripts/aevislauncher/"* "$INSTALL_PREFIX/share/kwin/scripts/aevislauncher/" 2>/dev/null || true
            $SUDO_CMD cp -rf "$CUTEFISH_ROOT/kwin-plugins/scripts/aevislauncher/"* "$INSTALL_PREFIX/share/kwin-wayland/scripts/aevislauncher/" 2>/dev/null || true
        fi

        # Ensure KWin window decoration symlink for Aevis
        for deco_dir in /usr/lib/qt6/plugins/org.kde.kdecoration3 /usr/lib/qt6/plugins/org.kde.kdecoration2; do
            if [ -f "$deco_dir/org.cutefish.decoration.so" ]; then
                $SUDO_CMD ln -sf org.cutefish.decoration.so "$deco_dir/org.aevis.decoration.so" 2>/dev/null || true
            fi
        done


        # Install system environment definitions so XDG_MENU_PREFIX and KWIN permission overrides
        # apply across all login shells, systemd user services, and compositor instances
        if [ -d "/etc/profile.d" ]; then
            echo -e "export XDG_MENU_PREFIX=cutefish-\nexport KWIN_WAYLAND_NO_PERMISSION_CHECKS=1" | $SUDO_CMD tee /etc/profile.d/cutefish-wayland.sh >/dev/null
        fi
        if [ -d "/usr/lib/environment.d" ]; then
            echo -e "XDG_MENU_PREFIX=cutefish-\nKWIN_WAYLAND_NO_PERMISSION_CHECKS=1" | $SUDO_CMD tee /usr/lib/environment.d/10-cutefish.conf >/dev/null
        elif [ -d "/etc/environment.d" ]; then
            echo -e "XDG_MENU_PREFIX=cutefish-\nKWIN_WAYLAND_NO_PERMISSION_CHECKS=1" | $SUDO_CMD tee /etc/environment.d/10-cutefish.conf >/dev/null
        fi

        # Clean up any legacy local binaries or links shadowing system-wide /usr/bin binaries
        if [ "$INSTALL_PREFIX" = "/usr" ]; then
            rm -f "$HOME/.local/bin/cutefish-"* 2>/dev/null || true
            $SUDO_CMD rm -f /usr/local/bin/cutefish-* 2>/dev/null || true
        fi

        # Refresh shared libraries and desktop databases
        log_info "Updating system linker cache (ldconfig)..."
        $SUDO_CMD ldconfig 2>/dev/null || true

        log_info "Updating desktop and icon databases..."
        $SUDO_CMD update-desktop-database "$INSTALL_PREFIX/share/applications" 2>/dev/null || true
        $SUDO_CMD gtk-update-icon-cache -f "$INSTALL_PREFIX/share/icons/Cutefish" 2>/dev/null || true
        $SUDO_CMD gtk-update-icon-cache -f "$INSTALL_PREFIX/share/icons/hicolor" 2>/dev/null || true
        fc-cache -f 2>/dev/null || true

        if command -v kbuildsycoca6 &>/dev/null; then
            log_info "Rebuilding KDE sycoca database (kbuildsycoca6)..."
            XDG_MENU_PREFIX=cutefish- kbuildsycoca6 --noincremental 2>/dev/null || true
        elif command -v kbuildsycoca5 &>/dev/null; then
            log_info "Rebuilding KDE sycoca database (kbuildsycoca5)..."
            XDG_MENU_PREFIX=cutefish- kbuildsycoca5 --noincremental 2>/dev/null || true
        fi

        if command -v glib-compile-schemas &>/dev/null && [ -d "$INSTALL_PREFIX/share/glib-2.0/schemas" ]; then
            $SUDO_CMD glib-compile-schemas "$INSTALL_PREFIX/share/glib-2.0/schemas" 2>/dev/null || true
        fi
    fi
    log_success "Desktop session registration and system caches refreshed."
fi

# ==============================================================================
# Complete
# ==============================================================================
echo ""
echo -e "${GREEN}================================================================${NC}"
echo -e "${BOLD}${GREEN}  Project Aevis Desktop Environment installation completed!     ${NC}"
echo -e "${GREEN}================================================================${NC}"
echo ""
echo -e "You can now select ${BOLD}Aevis (Wayland)${NC} or ${BOLD}Cutefish (Wayland)${NC} from your display manager (SDDM/GDM/LightDM),"
echo -e "or start the session manually using: ${CYAN}aevis-wayland-session${NC} (or ${CYAN}cutefish-wayland-session${NC})"
echo ""

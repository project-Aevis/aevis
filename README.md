# Aevis Desktop Environment

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)
[![GitHub Organization](https://img.shields.io/badge/GitHub-project--Aevis-181717?logo=github)](https://github.com/project-Aevis)

**Aevis Desktop Environment** is a modern, elegant, and lightweight desktop environment for Linux built with C++20, Qt 6, and KDE Frameworks 6. Designed for speed, simplicity, and a beautiful user experience.

---

## 🚀 Key Features

- **Modern Architecture**: Built on Qt 6, C++20, and Wayland (KWin 6).
- **Unified Shell**: Fast, responsive desktop shell combining status bar, dock, launcher, and desktop overview into a single optimized process.
- **FishUI Design System**: Clean, responsive QML control library with dark/light themes, blur effects, rounded corners, and native desktop integration.
- **Modular Sub-systems**: Dedicated applications for File Management, System Settings, Task Manager, Terminal, Photos, Calculator, and System Updates.
- **Customizable Theming**: Integrated Qt/GTK themes, SDDM login theme, Plymouth boot screen, cursor themes, and wallpapers.

---

## 📦 Project Structure & Repositories

| Repository | Description |
| :--- | :--- |
| **[aevis](https://github.com/project-Aevis/aevis)** | Workspace meta-repository & orchestration build scripts |
| **[shell](https://github.com/project-Aevis/shell)** | Core desktop shell (status bar, dock, launcher, desktop windows) |
| **[core](https://github.com/project-Aevis/core)** | Session manager, polkit agent, and background services |
| **[cutefish-framework](https://github.com/project-Aevis/cutefish-framework)** | Shared system C++/QML APIs (audio, bluetooth, display, network) |
| **[fishui](https://github.com/project-Aevis/fishui)** | Qt Quick control library and design system |
| **[filemanager](https://github.com/project-Aevis/filemanager)** | Fast, modern file manager |
| **[settings](https://github.com/project-Aevis/settings)** | Modular System Settings application |
| **[terminal](https://github.com/project-Aevis/terminal)** | Native terminal emulator |
| **[photos](https://github.com/project-Aevis/photos)** | Photo viewer and media library app |
| **[calculator](https://github.com/project-Aevis/calculator)** | Desktop calculator app |
| **[task-manager](https://github.com/project-Aevis/task-manager)** | System monitor and task manager |
| **[screenshot](https://github.com/project-Aevis/screenshot)** | Screenshot & screen capture tool |
| **[updator](https://github.com/project-Aevis/updator)** | System update utility |
| **[kwin-plugins](https://github.com/project-Aevis/kwin-plugins)** | KWin 6 window decorations, switcher, and effects |
| **[qt-plugins](https://github.com/project-Aevis/qt-plugins)** | Qt 6 theme integration plugin |
| **[gtk-themes](https://github.com/project-Aevis/gtk-themes)** | Matching GTK 3 / GTK 4 visual themes |
| **[icons](https://github.com/project-Aevis/icons)** | Official icon theme suite |
| **[cursor-themes](https://github.com/project-Aevis/cursor-themes)** | X11/Wayland cursor themes |
| **[sddm-theme](https://github.com/project-Aevis/sddm-theme)** | SDDM display manager theme |
| **[plymouth-theme](https://github.com/project-Aevis/plymouth-theme)** | Plymouth boot splash theme |
| **[wallpapers](https://github.com/project-Aevis/wallpapers)** | System wallpapers collection |
| **[screenlocker](https://github.com/project-Aevis/screenlocker)** | PAM-integrated screen locker |
| **[app](https://github.com/project-Aevis/app)** | HyperTube Music native application |

---

## 🛠️ Building & Installation

### Prerequisites

System dependencies (Debian/Ubuntu example):

```bash
sudo apt update
sudo apt install -y build-essential cmake pkg-config extra-cmake-modules \
    qt6-base-dev qt6-declarative-dev qt6-tools-dev \
    libkf6coreaddons-dev libkf6windowsystem-dev libkf6networkmanagerqt-dev \
    libkf6bluezqt-dev libkf6kio-dev libkdecorations3-dev kwin-dev
```

### Full System Build & Install

Run the included install script from the root repository:

```bash
# System-wide installation to /usr
sudo ./install.sh

# Or user-local installation
./local-install.sh
```

---

## 📄 License

Project Aevis components are released under the [GNU General Public License v3.0](LICENSE).

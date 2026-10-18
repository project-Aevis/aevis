// Aevis OS Website Interactive Script

document.addEventListener('DOMContentLoaded', () => {
    initTheme();
    initClock();
    initDockShowcase();
});

// 1. Theme Switcher (Dark / Light)
function initTheme() {
    const themeToggleBtn = document.getElementById('theme-toggle');
    const savedTheme = localStorage.getItem('aevis-theme') || 'dark';

    document.documentElement.setAttribute('data-theme', savedTheme);

    themeToggleBtn.addEventListener('click', () => {
        const currentTheme = document.documentElement.getAttribute('data-theme');
        const newTheme = currentTheme === 'dark' ? 'light' : 'dark';

        document.documentElement.setAttribute('data-theme', newTheme);
        localStorage.setItem('aevis-theme', newTheme);
    });
}

// 2. Real-time Statusbar Clock
function initClock() {
    const clockElem = document.getElementById('mock-clock');
    if (!clockElem) return;

    function updateTime() {
        const now = new Date();
        const options = { hour: 'numeric', minute: '2-digit', hour12: true };
        const timeStr = now.toLocaleTimeString([], options);
        const dayStr = now.toLocaleDateString([], { weekday: 'short', month: 'short', day: 'numeric' });
        clockElem.textContent = `${timeStr} • ${dayStr}`;
    }

    updateTime();
    setInterval(updateTime, 10000);
}

// 3. Interactive Dock Showcase Data & Switcher
const dockApps = {
    filemanager: {
        title: 'File Manager',
        desc: 'Org.cutefish.filemanager • Running (1 Window)',
        iconColor: '#3b82f6',
        svgPath: '<path d="M10 4H4c-1.1 0-1.99.9-1.99 2L2 18c0 1.1.9 2 2 2h16c1.1 0 2-.9 2-2V8c0-1.1-.9-2-2-2h-8l-2-2z"/>'
    },
    terminal: {
        title: 'Terminal',
        desc: 'Org.cutefish.terminal • Running (1 Active Session)',
        iconColor: '#10b981',
        svgPath: '<path d="M20 4H4c-1.1 0-2 .9-2 2v12c0 1.1.9 2 2 2h16c1.1 0 2-.9 2-2V6c0-1.1-.9-2-2-2zm0 14H4V8h16v10zm-16-12v-2h16v2H4zm3 5l4 3-4 3v-2l1.5-1L7 11v-2zm9 4h-5v-2h5v2z"/>'
    },
    music: {
        title: 'HyperTube Music',
        desc: 'Com.aevis.hypertube • C++20 Qt Media Engine Playing',
        iconColor: '#ec4899',
        svgPath: '<path d="M12 3v10.55c-.59-.34-1.27-.55-2-.55-2.21 0-4 1.79-4 4s1.79 4 4 4 4-1.79 4-4V7h4V3h-6z"/>'
    },
    settings: {
        title: 'Control Center',
        desc: 'Org.cutefish.settings • System Control Module Active',
        iconColor: '#6366f1',
        svgPath: '<path d="M19.14 12.94c.04-.3.06-.61.06-.94 0-.32-.02-.64-.07-.94l2.03-1.58c.18-.14.23-.41.12-.61l-1.92-3.32c-.12-.22-.37-.29-.59-.22l-2.39.96c-.5-.38-1.03-.7-1.62-.94l-.36-2.54c-.04-.24-.24-.41-.48-.41h-3.84c-.24 0-.43.17-.47.41l-.36 2.54c-.59.24-1.13.57-1.62.94l-2.39-.96c-.22-.08-.47 0-.59.22L2.74 8.87c-.12.21-.08.47.12.61l2.03 1.58c-.05.3-.09.63-.09.94s.02.64.07.94l-2.03 1.58c-.18.14-.23.41-.12.61l1.92 3.32c.12.22.37.29.59.22l2.39-.96c.5.38 1.03.7 1.62.94l.36 2.54c.05.24.24.41.48.41h3.84c.24 0 .44-.17.47-.41l.36-2.54c.59-.24 1.13-.56 1.62-.94l2.39.96c.22.08.47 0 .59-.22l1.92-3.32c.12-.22.07-.47-.12-.61l-2.01-1.58zM12 15.6c-1.98 0-3.6-1.62-3.6-3.6s1.62-3.6 3.6-3.6 3.6 1.62 3.6 3.6-1.62 3.6-3.6 3.6z"/>'
    }
};

function selectDockItem(appKey) {
    const app = dockApps[appKey];
    if (!app) return;

    const demoTitle = document.getElementById('dock-demo-title');
    const demoDesc = document.getElementById('dock-demo-desc');
    const demoIcon = document.getElementById('dock-demo-icon');

    demoTitle.textContent = app.title;
    demoDesc.textContent = app.desc;
    demoIcon.innerHTML = `<svg viewBox="0 0 24 24" width="48" height="48" fill="${app.iconColor}">${app.svgPath}</svg>`;

    // Update active button state
    const dockButtons = document.querySelectorAll('.flat-dock-interactive .dock-btn');
    dockButtons.forEach(btn => btn.classList.remove('active'));
    const evt = window.event;
    if (evt && evt.currentTarget) {
        evt.currentTarget.classList.add('active');
    }
}

function initDockShowcase() {
    // Default selected item is filemanager
}

// 4. Interactive Control Center Tile Toggle
function toggleTile(tileId) {
    const tile = document.getElementById(`tile-${tileId}`);
    const subText = document.getElementById(`sub-${tileId}`);
    if (!tile) return;

    tile.classList.toggle('active');
    const isActive = tile.classList.contains('active');

    const statuses = {
        wifi: isActive ? 'Connected • Aevis-5G' : 'Disconnected',
        bt: isActive ? 'On • Audio Headset' : 'Off',
        dnd: isActive ? 'Enabled (Silent)' : 'Disabled',
        night: isActive ? 'Active (3400K)' : 'Inactive'
    };

    if (subText && statuses[tileId]) {
        subText.textContent = statuses[tileId];
    }
}

// Accent Color Switcher
function setAccent(colorHex) {
    document.documentElement.style.setProperty('--accent-primary', colorHex);

    // Calculate hover color tint
    document.documentElement.style.setProperty('--accent-hover', colorHex);
    document.documentElement.style.setProperty('--accent-light', `${colorHex}25`);

    const buttons = document.querySelectorAll('.accent-btn');
    buttons.forEach(btn => btn.classList.remove('active'));
    const evt = window.event;
    if (evt && evt.currentTarget) {
        evt.currentTarget.classList.add('active');
    }
}

// 5. Interactive HyperTube Music App
let isPlaying = true;
function toggleMusicPlay() {
    const playIcon = document.getElementById('play-icon');
    isPlaying = !isPlaying;
    playIcon.textContent = isPlaying ? '⏸️' : '▶️';
}

function switchMusicTab(tabName) {
    const tabs = document.querySelectorAll('.ht-tab');
    tabs.forEach(tab => tab.classList.remove('active'));
    const evt = window.event;
    if (evt && evt.currentTarget) {
        evt.currentTarget.classList.add('active');
    }

    const views = document.querySelectorAll('.ht-view');
    views.forEach(view => view.classList.remove('active'));

    const targetView = document.getElementById(`ht-view-${tabName}`);
    if (targetView) {
        targetView.classList.add('active');
    }
}

// 6. Installation Code Tabs & Copy Button
function switchCodeTab(tabId) {
    const tabs = document.querySelectorAll('.code-tab');
    tabs.forEach(tab => tab.classList.remove('active'));
    const evt = window.event;
    if (evt && evt.currentTarget) {
        evt.currentTarget.classList.add('active');
    }

    const contents = document.querySelectorAll('.code-content');
    contents.forEach(content => content.classList.remove('active'));

    const targetContent = document.getElementById(`code-${tabId}`);
    if (targetContent) {
        targetContent.classList.add('active');
    }
}

function copyCode(codeElemId) {
    const codeElem = document.getElementById(codeElemId);
    if (!codeElem) return;

    navigator.clipboard.writeText(codeElem.textContent).then(() => {
        const btn = event.currentTarget;
        const originalText = btn.textContent;
        btn.textContent = 'Copied!';
        btn.style.backgroundColor = 'var(--flat-green)';
        btn.style.color = '#ffffff';

        setTimeout(() => {
            btn.textContent = originalText;
            btn.style.backgroundColor = '';
            btn.style.color = '';
        }, 2000);
    });
}

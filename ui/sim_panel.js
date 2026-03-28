(function () {
  const STYLE_ID = 'az5pd-sim-panel-style';
  const SHELL_ID = 'sim-shell';
  const HUD_ID = 'sim-hud';
  const state = {
    open: false,
    section: 'overview',
    data: {},
    hudEditing: false,
    hudEditSnapshot: null,
    ui: {
      top: 92,
      left: null,
      width: 640,
      height: 720
    }
  };

  const UI_STORAGE_KEY = 'az5pd:simPanelUI';
  const HUD_STORAGE_KEY = 'az5pd:simHudUI';
  const MIN_WIDTH = 520;
  const MIN_HEIGHT = 420;
  const HUD_DEFAULTS = {
    top: 56,
    left: 54,
    width: 760,
    collapsed: false,
    hidden: false
  };

  function send(event, payload) {
    try {
      fetch(`https://${GetParentResourceName()}/${event}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(payload || {})
      }).catch(() => {});
    } catch (_) {}
  }

  function esc(str) {
    return String(str == null ? '' : str)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#039;');
  }

  function trim(str, len) {
    const out = String(str == null ? '' : str).replace(/\s+/g, ' ').trim();
    return len && out.length > len ? `${out.slice(0, len - 1)}…` : out;
  }

  function clamp(value, min, max) {
    return Math.min(Math.max(value, min), max);
  }

  function loadUIState() {
    try {
      const raw = window.localStorage.getItem(UI_STORAGE_KEY);
      if (!raw) return;
      const parsed = JSON.parse(raw);
      if (!parsed || typeof parsed !== 'object') return;
      if (Number.isFinite(parsed.top)) state.ui.top = parsed.top;
      if (Number.isFinite(parsed.left)) state.ui.left = parsed.left;
      if (Number.isFinite(parsed.width)) state.ui.width = parsed.width;
      if (Number.isFinite(parsed.height)) state.ui.height = parsed.height;
    } catch (_) {}
  }

  function saveUIState() {
    try {
      window.localStorage.setItem(UI_STORAGE_KEY, JSON.stringify(state.ui));
    } catch (_) {}
  }

  function fitUIToViewport() {
    const margin = 18;
    const maxWidth = Math.max(MIN_WIDTH, window.innerWidth - margin * 2);
    const maxHeight = Math.max(MIN_HEIGHT, window.innerHeight - margin * 2);
    state.ui.width = clamp(state.ui.width || 640, MIN_WIDTH, maxWidth);
    state.ui.height = clamp(state.ui.height || Math.min(720, maxHeight), MIN_HEIGHT, maxHeight);
    if (!Number.isFinite(state.ui.left)) {
      state.ui.left = Math.max(margin, window.innerWidth - state.ui.width - 24);
    }
    state.ui.left = clamp(state.ui.left, margin, Math.max(margin, window.innerWidth - state.ui.width - margin));
    state.ui.top = clamp(state.ui.top || 92, margin, Math.max(margin, window.innerHeight - state.ui.height - margin));
  }

  function applyUIBounds() {
    const shell = document.getElementById(SHELL_ID);
    if (!shell) return;
    fitUIToViewport();
    shell.style.top = `${state.ui.top}px`;
    shell.style.left = `${state.ui.left}px`;
    shell.style.width = `${state.ui.width}px`;
    shell.style.height = `${state.ui.height}px`;
  }


  function loadHUDState() {
    state.hud = { ...(HUD_DEFAULTS || {}) };
    try {
      const raw = window.localStorage.getItem(HUD_STORAGE_KEY);
      if (!raw) return;
      const parsed = JSON.parse(raw);
      if (!parsed || typeof parsed !== 'object') return;
      if (Number.isFinite(parsed.top)) state.hud.top = parsed.top;
      if (Number.isFinite(parsed.left)) state.hud.left = parsed.left;
      if (Number.isFinite(parsed.width)) state.hud.width = parsed.width;
      if (typeof parsed.collapsed === 'boolean') state.hud.collapsed = parsed.collapsed;
      if (typeof parsed.hidden === 'boolean') state.hud.hidden = parsed.hidden;
    } catch (_) {}
  }

  function saveHUDState() {
    try {
      window.localStorage.setItem(HUD_STORAGE_KEY, JSON.stringify(state.hud || HUD_DEFAULTS));
    } catch (_) {}
  }

  function fitHUDToViewport() {
    state.hud = state.hud || { ...(HUD_DEFAULTS || {}) };
    const margin = 12;
    const maxWidth = Math.max(360, window.innerWidth - margin * 2);
    state.hud.width = clamp(state.hud.width || HUD_DEFAULTS.width, 420, Math.min(860, maxWidth));
    if (!Number.isFinite(state.hud.left)) state.hud.left = HUD_DEFAULTS.left;
    if (!Number.isFinite(state.hud.top)) state.hud.top = HUD_DEFAULTS.top;
    const hud = document.getElementById(HUD_ID);
    const approxHeight = state.hud.collapsed ? 48 : Math.min(148, (hud && hud.offsetHeight) || 148);
    state.hud.left = clamp(state.hud.left, margin, Math.max(margin, window.innerWidth - state.hud.width - margin));
    state.hud.top = clamp(state.hud.top, margin, Math.max(margin, window.innerHeight - approxHeight - margin));
  }

  function applyHUDBounds() {
    const hud = document.getElementById(HUD_ID);
    if (!hud) return;
    fitHUDToViewport();
    const interactive = state.open === true || state.hudEditing === true;
    hud.style.top = `${state.hud.top}px`;
    hud.style.left = `${state.hud.left}px`;
    hud.style.width = `${state.hud.width}px`;
    hud.style.pointerEvents = interactive ? 'auto' : 'none';
    hud.style.display = state.hud.hidden === true ? 'none' : 'block';
    hud.classList.toggle('collapsed', state.hud.collapsed === true);
    hud.classList.toggle('interactive', interactive);
    hud.classList.toggle('editing', state.hudEditing === true);
  }

  function injectStyle() {
    if (document.getElementById(STYLE_ID)) return;
    const style = document.createElement('style');
    style.id = STYLE_ID;
    style.textContent = `
      #${SHELL_ID} {
        display:none;
        position:absolute;
        top:92px;
        left:calc(100vw - 664px);
        width:640px;
        max-width:calc(100vw - 36px);
        height:min(720px, calc(100vh - 36px));
        border-radius:14px;
        background:linear-gradient(180deg, rgba(13,25,40,0.95), rgba(6,12,22,0.94));
        border:1px solid rgba(62,118,204,0.35);
        box-shadow:0 22px 50px rgba(0,0,0,0.46), inset 0 1px 0 rgba(255,255,255,0.05);
        color:#eef4ff;
        z-index:100050;
        overflow:hidden;
        backdrop-filter: blur(10px);
        user-select:none;
        -webkit-user-select:none;
      }
      body.sim-panel-moving, body.sim-panel-moving * {
        user-select:none !important;
        -webkit-user-select:none !important;
        cursor:grabbing !important;
      }
      #${SHELL_ID}, #${SHELL_ID} * { box-sizing:border-box; }
      #${SHELL_ID}.open { display:flex; flex-direction:column; }
      #${SHELL_ID} .sim-header {
        display:flex; align-items:center; justify-content:space-between;
        padding:14px 16px;
        border-bottom:1px solid rgba(255,255,255,0.06);
        background:linear-gradient(180deg, rgba(28,56,102,0.85), rgba(16,31,58,0.78));
        cursor:grab;
      }
      #${SHELL_ID} .sim-header:active { cursor:grabbing; }
      #${SHELL_ID} .sim-title-wrap { display:flex; flex-direction:column; gap:3px; }
      #${SHELL_ID} .sim-title { font-size:18px; font-weight:800; letter-spacing:.4px; }
      #${SHELL_ID} .sim-subtitle { font-size:12px; color:rgba(224,235,255,0.76); }
      #${SHELL_ID} .sim-head-actions { display:flex; gap:8px; align-items:center; }
      #${SHELL_ID} .sim-icon-btn {
        width:34px; height:34px; border-radius:10px; border:1px solid rgba(255,255,255,0.08);
        background:rgba(255,255,255,0.06); color:#fff; cursor:pointer; font-size:15px;
      }
      #${SHELL_ID} .sim-icon-btn:hover,
      #${SHELL_ID} .sim-nav-btn:hover,
      #${SHELL_ID} .sim-btn:hover { filter:brightness(1.06); }
      #${SHELL_ID} button { outline:none; }
      #${SHELL_ID} button::-moz-focus-inner { border:0; }
      #${SHELL_ID} .sim-statusbar {
        display:grid; grid-template-columns:repeat(3, 1fr); gap:10px; padding:12px 16px;
        background:rgba(9,17,30,0.75); border-bottom:1px solid rgba(255,255,255,0.05);
      }
      #${SHELL_ID} .sim-pill {
        background:rgba(255,255,255,0.05); border:1px solid rgba(255,255,255,0.05); border-radius:12px;
        padding:10px 12px;
      }
      #${SHELL_ID} .sim-pill-label { font-size:11px; text-transform:uppercase; letter-spacing:.7px; color:rgba(206,221,252,0.62); }
      #${SHELL_ID} .sim-pill-value { margin-top:4px; font-size:14px; font-weight:700; }
      #${SHELL_ID} .sim-body { display:grid; grid-template-columns:180px 1fr; min-height:0; flex:1; }
      #${SHELL_ID} .sim-nav {
        background:rgba(8,14,24,0.66); border-right:1px solid rgba(255,255,255,0.06);
        padding:12px; display:flex; flex-direction:column; gap:8px; overflow:auto;
      }
      #${SHELL_ID} .sim-nav-btn {
        width:100%; text-align:left; border:none; cursor:pointer; padding:12px 12px; border-radius:12px;
        background:transparent; color:rgba(229,238,255,0.78); font-weight:700; line-height:1.2;
      }
      #${SHELL_ID} .sim-nav-btn small { display:block; margin-top:5px; color:rgba(194,210,245,0.52); font-weight:500; }
      #${SHELL_ID} .sim-nav-btn.active { background:linear-gradient(180deg, rgba(61,116,212,0.32), rgba(39,77,145,0.22)); color:#fff; box-shadow:inset 0 0 0 1px rgba(103,161,255,0.22); }
      #${SHELL_ID} .sim-content { min-height:0; display:flex; flex-direction:column; }
      #${SHELL_ID} .sim-content-scroll { padding:16px; overflow:auto; min-height:0; display:flex; flex-direction:column; gap:14px; }
      #${SHELL_ID} .sim-section-title { font-size:18px; font-weight:800; }
      #${SHELL_ID} .sim-section-sub { font-size:12px; color:rgba(208,221,246,0.65); margin-top:4px; }
      #${SHELL_ID} .sim-card {
        background:rgba(255,255,255,0.045); border:1px solid rgba(255,255,255,0.06); border-radius:14px;
        padding:14px; box-shadow: inset 0 1px 0 rgba(255,255,255,0.04);
      }
      #${SHELL_ID} .sim-card h4 { margin:0 0 10px; font-size:14px; font-weight:800; }
      #${SHELL_ID} .sim-grid { display:grid; grid-template-columns:repeat(2, minmax(0, 1fr)); gap:12px; }
      #${SHELL_ID} .sim-grid-3 { display:grid; grid-template-columns:repeat(3, minmax(0, 1fr)); gap:10px; }
      #${SHELL_ID} .sim-meta { font-size:12px; color:rgba(208,221,246,0.72); line-height:1.5; }
      #${SHELL_ID} .sim-strong { font-weight:800; color:#fff; }
      #${SHELL_ID} .sim-actions { display:flex; flex-wrap:wrap; gap:8px; }
      #${SHELL_ID} .sim-btn {
        border:none; cursor:pointer; border-radius:11px; padding:10px 12px; font-weight:800; font-size:12px;
        color:#fff; background:rgba(255,255,255,0.08); border:1px solid rgba(255,255,255,0.06);
      }
      #${SHELL_ID} .sim-btn.primary { background:linear-gradient(180deg, #3f81ed, #2758b9); }
      #${SHELL_ID} .sim-btn.warn { background:linear-gradient(180deg, #d94e4e, #aa2d2d); }
      #${SHELL_ID} .sim-list { display:flex; flex-direction:column; gap:10px; }
      #${SHELL_ID} .sim-list-item {
        padding:12px; border-radius:12px; background:rgba(255,255,255,0.04); border:1px solid rgba(255,255,255,0.05);
      }
      #${SHELL_ID} .sim-list-head { display:flex; justify-content:space-between; gap:10px; font-weight:800; }
      #${SHELL_ID} .sim-badge {
        font-size:11px; padding:4px 7px; border-radius:999px; background:rgba(61,129,237,0.22); color:#cfe1ff;
      }
      #${SHELL_ID} .sim-empty { padding:20px; text-align:center; color:rgba(208,221,246,0.64); font-style:italic; }
      #${SHELL_ID} .sim-note {
        padding:12px 14px; border-radius:12px; background:rgba(52,102,190,0.16); border:1px solid rgba(83,138,239,0.22);
        color:#d6e6ff; font-size:12px; line-height:1.5;
      }
      #${SHELL_ID} .sim-resize-grip {
        position:absolute;
        right:10px;
        bottom:10px;
        width:22px;
        height:22px;
        cursor:nwse-resize;
        display:flex;
        align-items:center;
        justify-content:center;
        border-radius:8px;
        background:rgba(255,255,255,0.03);
        border:1px solid rgba(255,255,255,0.06);
      }
      #${SHELL_ID} .sim-resize-grip::before,
      #${SHELL_ID} .sim-resize-grip::after {
        content:'';
        position:absolute;
        right:5px;
        bottom:5px;
        width:10px;
        height:2px;
        background:rgba(205,224,255,0.7);
        transform:rotate(-45deg);
        border-radius:2px;
      }
      #${SHELL_ID} .sim-resize-grip::after {
        right:8px;
        bottom:10px;
        width:6px;
        opacity:0.75;
      }
      #${SHELL_ID} .sim-content-scroll::selection,
      #${SHELL_ID} .sim-nav::selection,
      #${SHELL_ID} .sim-header::selection,
      #${SHELL_ID} *::selection { background:transparent; }
      @media (max-width: 920px) {
        #${SHELL_ID} { left:18px !important; width:calc(100vw - 36px) !important; top:64px !important; height:calc(100vh - 82px) !important; }
        #${SHELL_ID} .sim-body { grid-template-columns:1fr; }
        #${SHELL_ID} .sim-nav { flex-direction:row; flex-wrap:wrap; }
        #${SHELL_ID} .sim-nav-btn { width:calc(50% - 4px); }
        #${SHELL_ID} .sim-statusbar, #${SHELL_ID} .sim-grid, #${SHELL_ID} .sim-grid-3 { grid-template-columns:1fr; }
      }
    `;

    style.textContent += `
      #${HUD_ID} {
        display:none;
        position:fixed;
        top:56px;
        left:54px;
        width:min(760px, calc(100vw - 24px));
        z-index:100025;
        pointer-events:none;
        color:#f7fbff;
      }
      #${HUD_ID}.open { display:block; }
      #${HUD_ID}.interactive { pointer-events:auto; }
      #${HUD_ID}, #${HUD_ID} * {
        user-select:none;
        -webkit-user-select:none;
      }
      #${HUD_ID} .sim-hud-head,
      #${HUD_ID} .sim-hud-resize,
      #${HUD_ID} .sim-hud-btn {
        touch-action:none;
      }
      #${HUD_ID} .sim-hud-frame {
        width:100%;
        position:relative;
        border-radius:16px;
        background:linear-gradient(180deg, rgba(24,30,40,0.92), rgba(14,18,25,0.88));
        border:1px solid rgba(255,153,52,0.18);
        box-shadow:0 16px 38px rgba(0,0,0,0.30), inset 0 1px 0 rgba(255,255,255,0.05);
        backdrop-filter:blur(10px);
        overflow:hidden;
      }
      #${HUD_ID} .sim-hud-head {
        position:relative;
        display:flex;
        align-items:center;
        justify-content:space-between;
        gap:10px;
        padding:9px 12px;
        min-height:48px;
        border-bottom:1px solid rgba(255,255,255,0.05);
        background:linear-gradient(180deg, rgba(39,46,60,0.92), rgba(27,32,42,0.88));
        cursor:default;
      }
      #${HUD_ID}.editing .sim-hud-head { cursor:move; }
      #${HUD_ID}.interactive .sim-hud-head { cursor:grab; }
      #${HUD_ID}.interactive .sim-hud-head:active { cursor:grabbing; }
      #${HUD_ID} .sim-hud-dragzone { display:none; }
      #${HUD_ID} .sim-hud-title-wrap { min-width:0; }
      #${HUD_ID}.editing .sim-hud-title-wrap,
      #${HUD_ID}.editing .sim-hud-title,
      #${HUD_ID}.editing .sim-hud-mini,
      #${HUD_ID}.editing .sim-hud-edit-note,
      #${HUD_ID}.editing .sim-hud-grip {
        pointer-events:none;
      }
      #${HUD_ID} .sim-hud-title {
        font-size:11px;
        font-weight:900;
        text-transform:uppercase;
        letter-spacing:1px;
        color:rgba(234,240,250,0.72);
      }
      #${HUD_ID} .sim-hud-mini {
        margin-top:3px;
        font-size:13px;
        font-weight:800;
        color:#ffffff;
        white-space:nowrap;
        overflow:hidden;
        text-overflow:ellipsis;
      }
      #${HUD_ID} .sim-hud-controls { display:flex; gap:6px; align-items:center; }
      #${HUD_ID} .sim-hud-btn {
        width:28px;
        height:28px;
        border-radius:8px;
        border:1px solid rgba(255,255,255,0.08);
        background:rgba(255,255,255,0.05);
        color:#f7fbff;
        cursor:pointer;
        font-weight:800;
      }
      #${HUD_ID} .sim-hud-btn:hover { filter:brightness(1.08); }
      #${HUD_ID} .sim-hud-btn.text {
        width:auto;
        min-width:62px;
        padding:0 10px;
        font-size:12px;
      }
      #${HUD_ID} .sim-hud-controls.edit-controls { display:none; flex-wrap:wrap; justify-content:flex-end; }
      #${HUD_ID}.editing .sim-hud-controls.normal-controls { display:none; }
      #${HUD_ID}.editing .sim-hud-controls.edit-controls { display:flex; }
      #${HUD_ID} .sim-hud-btn.nudge { min-width:32px; width:32px; padding:0; }
      #${HUD_ID} .sim-hud-btn.size { min-width:36px; width:36px; padding:0; }
      #${HUD_ID} .sim-hud-edit-note {
        display:none;
        padding:8px 12px 0;
        font-size:11px;
        color:rgba(255,207,160,0.92);
      }
      #${HUD_ID}.editing .sim-hud-edit-note { display:block; }
      #${HUD_ID} .sim-hud-body {
        display:grid;
        grid-template-columns:1.2fr 1fr 1fr;
        gap:8px;
        padding:10px;
      }
      #${HUD_ID}.collapsed .sim-hud-body { display:none; }
      #${HUD_ID} .sim-hud-card {
        min-width:0;
        padding:10px 12px;
        border-radius:12px;
        background:linear-gradient(180deg, rgba(31,35,42,0.82), rgba(17,20,26,0.80));
        border:1px solid rgba(255,163,72,0.16);
        border-left:3px solid rgba(255,145,34,0.90);
        box-shadow:inset 0 1px 0 rgba(255,255,255,0.04);
      }
      #${HUD_ID} .sim-hud-card.emergency {
        border-left-color:#ff5e52;
        border-color:rgba(255,106,92,0.24);
      }
      #${HUD_ID} .sim-hud-row {
        display:flex;
        align-items:flex-start;
        justify-content:space-between;
        gap:8px;
      }
      #${HUD_ID} .sim-hud-label {
        font-size:10px;
        font-weight:800;
        text-transform:uppercase;
        letter-spacing:0.95px;
        color:rgba(214,223,236,0.58);
      }
      #${HUD_ID} .sim-hud-value {
        margin-top:3px;
        font-size:18px;
        line-height:1.05;
        font-weight:900;
        letter-spacing:.2px;
        color:#ffffff;
        white-space:nowrap;
        overflow:hidden;
        text-overflow:ellipsis;
      }
      #${HUD_ID} .sim-hud-sub {
        margin-top:6px;
        font-size:12px;
        line-height:1.38;
        color:rgba(229,236,248,0.82);
      }
      #${HUD_ID} .sim-hud-sub strong { color:#fff; font-weight:800; }
      #${HUD_ID} .sim-hud-tag {
        flex:0 0 auto;
        padding:5px 8px;
        border-radius:999px;
        background:rgba(255,255,255,0.06);
        border:1px solid rgba(255,255,255,0.07);
        color:#dfe8f6;
        font-size:10px;
        font-weight:800;
        letter-spacing:.35px;
        white-space:nowrap;
      }
      #${HUD_ID} .sim-hud-accent { color:#ffb66d; }
      #${HUD_ID} .sim-hud-grip {
        display:none;
        width:12px;
        height:28px;
        opacity:0.55;
        margin-right:4px;
        position:relative;
      }
      #${HUD_ID}.interactive .sim-hud-grip { display:block; }
      #${HUD_ID} .sim-hud-grip::before {
        content:'';
        position:absolute;
        inset:4px 4px;
        border-left:2px dotted rgba(224,232,246,0.58);
      }
      #${HUD_ID} .sim-hud-resize {
        display:none;
        position:absolute;
        right:10px;
        bottom:10px;
        width:22px;
        height:22px;
        cursor:nwse-resize;
        border-radius:8px;
        background:rgba(255,255,255,0.04);
        border:1px solid rgba(255,255,255,0.08);
      }
      #${HUD_ID} .sim-hud-resize::before,
      #${HUD_ID} .sim-hud-resize::after {
        content:'';
        position:absolute;
        right:5px;
        bottom:5px;
        width:10px;
        height:2px;
        background:rgba(224,232,246,0.72);
        transform:rotate(-45deg);
        border-radius:2px;
      }
      #${HUD_ID} .sim-hud-resize::after {
        right:8px;
        bottom:10px;
        width:6px;
        opacity:0.75;
      }
      #${HUD_ID}.editing .sim-hud-resize { display:block; }
      @media (max-width: 980px) {
        #${HUD_ID} { width:min(700px, calc(100vw - 20px)); left:10px; top:10px; }
        #${HUD_ID} .sim-hud-body { grid-template-columns:1fr; }
      }
    `;

    style.textContent += `
      #${SHELL_ID}, #${SHELL_ID} *, #${HUD_ID}, #${HUD_ID} * {
        user-select:none !important;
        -webkit-user-select:none !important;
        -webkit-user-drag:none !important;
      }
      #${SHELL_ID}, #${SHELL_ID} .sim-header, #${SHELL_ID} .sim-statusbar, #${SHELL_ID} .sim-nav,
      #${SHELL_ID} .sim-pill, #${SHELL_ID} .sim-card, #${SHELL_ID} .sim-nav-btn, #${SHELL_ID} .sim-btn,
      #${SHELL_ID} .sim-list-item, #${SHELL_ID} .sim-note, #${SHELL_ID} .sim-icon-btn, #${SHELL_ID} .sim-resize-grip,
      #${HUD_ID} .sim-hud-frame, #${HUD_ID} .sim-hud-head, #${HUD_ID} .sim-hud-card, #${HUD_ID} .sim-hud-btn,
      #${HUD_ID} .sim-hud-tag, #${HUD_ID} .sim-hud-resize {
        border:none !important;
        box-shadow:none !important;
      }
      #${SHELL_ID} .sim-statusbar, #${SHELL_ID} .sim-nav, #${SHELL_ID} .sim-header,
      #${HUD_ID} .sim-hud-head {
        border-bottom:none !important;
        border-right:none !important;
      }
      #${HUD_ID} .sim-hud-head, #${HUD_ID} .sim-hud-resize,
      #${SHELL_ID} .sim-header, #${SHELL_ID} .sim-resize-grip {
        touch-action:none !important;
      }
      #${HUD_ID} .sim-hud-title-wrap, #${HUD_ID} .sim-hud-title, #${HUD_ID} .sim-hud-mini, #${HUD_ID} .sim-hud-grip {
        pointer-events:none !important;
      }
      #${HUD_ID}.interactive .sim-hud-head, #${SHELL_ID} .sim-header {
        cursor:move !important;
      }
    `;

    document.head.appendChild(style);
  }

  function injectShell() {
    if (document.getElementById(SHELL_ID)) return document.getElementById(SHELL_ID);
    const shell = document.createElement('div');
    shell.id = SHELL_ID;
    shell.innerHTML = `
      <div class="sim-header">
        <div class="sim-title-wrap">
          <div class="sim-title">Az-5PD Simulation / Scene Tools</div>
          <div class="sim-subtitle">Integrated panel • no separate HUD</div>
        </div>
        <div class="sim-head-actions">
          <button class="sim-icon-btn" data-action="refreshState" title="Refresh">↻</button>
          <button class="sim-icon-btn" id="sim-close-btn" title="Close">✕</button>
        </div>
      </div>
      <div class="sim-statusbar" id="sim-statusbar"></div>
      <div class="sim-body">
        <div class="sim-nav" id="sim-nav"></div>
        <div class="sim-content">
          <div class="sim-content-scroll" id="sim-content"></div>
        </div>
      </div>
      <div class="sim-resize-grip" id="sim-resize-grip" title="Resize panel"></div>
    `;
    document.body.appendChild(shell);
    applyUIBounds();
    setupInteractions(shell);

    shell.addEventListener('click', (ev) => {
      const closeBtn = ev.target.closest('#sim-close-btn');
      if (closeBtn) {
        send('simClose', {});
        return;
      }
      const navBtn = ev.target.closest('.sim-nav-btn');
      if (navBtn) {
        state.section = navBtn.dataset.section || 'overview';
        render();
        return;
      }
      const actionBtn = ev.target.closest('[data-action]');
      if (actionBtn) {
        send('simAction', {
          action: actionBtn.dataset.action,
          id: actionBtn.dataset.id || '',
          section: state.section
        });
      }
    });

    return shell;
  }


  function injectHud() {
    let hud = document.getElementById(HUD_ID);
    if (hud) return hud;
    hud = document.createElement('div');
    hud.id = HUD_ID;
    hud.innerHTML = `
      <div class="sim-hud-frame">
        <div class="sim-hud-head">
          <div style="display:flex;align-items:center;min-width:0;gap:6px;position:relative;z-index:1;">
            <div class="sim-hud-grip" title="Drag HUD"></div>
            <div class="sim-hud-title-wrap">
              <div class="sim-hud-title" id="sim-hud-title">Az-5PD Sim HUD</div>
              <div class="sim-hud-mini" id="sim-hud-mini">Press /az5pdhud to move or resize this HUD.</div>
            </div>
          </div>
          <div class="sim-hud-controls normal-controls" style="position:relative;z-index:1;">
            <button class="sim-hud-btn" data-hud-action="collapse" title="Collapse / expand">—</button>
            <button class="sim-hud-btn" data-hud-action="edit" title="Edit HUD layout">✥</button>
            <button class="sim-hud-btn" data-action="toggleHud" title="Hide HUD">✕</button>
          </div>
          <div class="sim-hud-controls edit-controls" style="position:relative;z-index:1;">
            <button class="sim-hud-btn nudge" data-hud-action="nudgeLeft" title="Move left">←</button>
            <button class="sim-hud-btn nudge" data-hud-action="nudgeUp" title="Move up">↑</button>
            <button class="sim-hud-btn nudge" data-hud-action="nudgeDown" title="Move down">↓</button>
            <button class="sim-hud-btn nudge" data-hud-action="nudgeRight" title="Move right">→</button>
            <button class="sim-hud-btn size" data-hud-action="sizeDown" title="Make smaller">−</button>
            <button class="sim-hud-btn size" data-hud-action="sizeUp" title="Make larger">+</button>
            <button class="sim-hud-btn text" data-hud-action="resetDraft" title="Reset to default size and position">Reset</button>
            <button class="sim-hud-btn text" data-hud-action="cancel" title="Discard changes">Cancel</button>
            <button class="sim-hud-btn text" data-hud-action="save" title="Save HUD layout">Save</button>
          </div>
        </div>
        <div class="sim-hud-edit-note">HUD edit mode: drag the HUD header or resize from the bottom-right corner, then click Save.</div>
        <div class="sim-hud-body" id="sim-hud-body"></div>
        <div class="sim-hud-resize" id="sim-hud-resize" title="Resize HUD"></div>
      </div>
    `;
    document.body.appendChild(hud);
    setupHudInteractions(hud);
    applyHUDBounds();
    return hud;
  }

  function setupInteractions(shell) {
    if (!shell || shell.dataset.interactionsReady === '1') return;
    shell.dataset.interactionsReady = '1';

    const header = shell.querySelector('.sim-header');
    const resizeGrip = shell.querySelector('#sim-resize-grip');
    shell.addEventListener('selectstart', (ev) => ev.preventDefault());
    let dragState = null;
    let resizeState = null;

    const endInteractions = () => {
      dragState = null;
      resizeState = null;
      document.body.classList.remove('sim-panel-moving');
      saveUIState();
    };

    const onMove = (ev) => {
      if (dragState) {
        state.ui.left = dragState.startLeft + (ev.clientX - dragState.startX);
        state.ui.top = dragState.startTop + (ev.clientY - dragState.startY);
        applyUIBounds();
        return;
      }
      if (resizeState) {
        state.ui.width = resizeState.startWidth + (ev.clientX - resizeState.startX);
        state.ui.height = resizeState.startHeight + (ev.clientY - resizeState.startY);
        applyUIBounds();
      }
    };

    document.addEventListener('mousemove', onMove, { capture: true });
    document.addEventListener('mouseup', endInteractions, { capture: true });
    window.addEventListener('blur', endInteractions);

    if (header) {
      header.addEventListener('mousedown', (ev) => {
        if (ev.button !== 0) return;
        if (ev.target.closest('button, [data-action]')) return;
        ev.preventDefault();
        document.body.classList.add('sim-panel-moving');
        dragState = {
          startX: ev.clientX,
          startY: ev.clientY,
          startLeft: state.ui.left,
          startTop: state.ui.top
        };
      });
    }

    if (resizeGrip) {
      resizeGrip.addEventListener('mousedown', (ev) => {
        if (ev.button !== 0) return;
        ev.preventDefault();
        ev.stopPropagation();
        document.body.classList.add('sim-panel-moving');
        resizeState = {
          startX: ev.clientX,
          startY: ev.clientY,
          startWidth: state.ui.width,
          startHeight: state.ui.height
        };
      });
    }
  }



  function setupHudInteractions(hud) {
    if (!hud || hud.dataset.interactionsReady === '1') return;
    hud.dataset.interactionsReady = '1';
    const header = hud.querySelector('.sim-hud-head');
    const resizeGrip = hud.querySelector('#sim-hud-resize');
    hud.addEventListener('selectstart', (ev) => ev.preventDefault());
    let dragState = null;
    let resizeState = null;
    let activePointerId = null;

    const clearInteraction = (shouldSave) => {
      const hadInteraction = !!dragState || !!resizeState;
      dragState = null;
      resizeState = null;
      activePointerId = null;
      document.body.classList.remove('sim-panel-moving');
      document.body.style.userSelect = '';
      document.body.style.webkitUserSelect = '';
      document.documentElement.style.userSelect = '';
      document.documentElement.style.webkitUserSelect = '';
      if (hadInteraction && shouldSave && state.hudEditing !== true) saveHUDState();
    };

    const onMove = (clientX, clientY) => {
      if (dragState) {
        state.hud.left = dragState.startLeft + (clientX - dragState.startX);
        state.hud.top = dragState.startTop + (clientY - dragState.startY);
        applyHUDBounds();
        return true;
      }
      if (resizeState) {
        state.hud.width = resizeState.startWidth + (clientX - resizeState.startX);
        applyHUDBounds();
        return true;
      }
      return false;
    };

    const handlePointerMove = (ev) => {
      if (activePointerId !== null && ev.pointerId !== activePointerId) return;
      if (onMove(ev.clientX, ev.clientY)) ev.preventDefault();
    };

    const handleMouseMove = (ev) => {
      if (activePointerId !== null) return;
      if (onMove(ev.clientX, ev.clientY)) ev.preventDefault();
    };

    const handlePointerEnd = (ev) => {
      if (activePointerId !== null && ev.pointerId !== activePointerId) return;
      clearInteraction(true);
    };

    const handleMouseEnd = () => {
      if (activePointerId !== null) return;
      clearInteraction(true);
    };

    document.addEventListener('pointermove', handlePointerMove, { passive: false, capture: true });
    document.addEventListener('pointerup', handlePointerEnd, { passive: false, capture: true });
    document.addEventListener('pointercancel', handlePointerEnd, { passive: false, capture: true });
    document.addEventListener('mousemove', handleMouseMove, { passive: false, capture: true });
    document.addEventListener('mouseup', handleMouseEnd, { passive: false, capture: true });
    window.addEventListener('blur', () => clearInteraction(true));

    if (header) {
      const startDrag = (ev) => {
        const isPointer = typeof ev.pointerId === 'number';
        if (state.hudEditing !== true) return;
        if ((ev.button ?? 0) !== 0) return;
        if (ev.target && ev.target.closest && ev.target.closest('.sim-hud-controls, .sim-hud-btn, #sim-hud-resize')) return;
        ev.preventDefault();
        ev.stopPropagation();
        document.body.classList.add('sim-panel-moving');
        document.body.style.userSelect = 'none';
        document.body.style.webkitUserSelect = 'none';
        document.documentElement.style.userSelect = 'none';
        document.documentElement.style.webkitUserSelect = 'none';
        activePointerId = isPointer ? ev.pointerId : null;
        dragState = {
          startX: ev.clientX,
          startY: ev.clientY,
          startLeft: state.hud.left,
          startTop: state.hud.top
        };
        resizeState = null;
        if (isPointer && header.setPointerCapture) {
          try { header.setPointerCapture(ev.pointerId); } catch (_) {}
        }
      };
      header.addEventListener('pointerdown', startDrag, { passive: false });
      header.addEventListener('mousedown', startDrag);
    }

    if (resizeGrip) {
      const startResize = (ev) => {
        const isPointer = typeof ev.pointerId === 'number';
        if (state.hudEditing !== true) return;
        if ((ev.button ?? 0) !== 0) return;
        ev.preventDefault();
        ev.stopPropagation();
        document.body.classList.add('sim-panel-moving');
        document.body.style.userSelect = 'none';
        document.body.style.webkitUserSelect = 'none';
        document.documentElement.style.userSelect = 'none';
        document.documentElement.style.webkitUserSelect = 'none';
        activePointerId = isPointer ? ev.pointerId : null;
        resizeState = {
          startX: ev.clientX,
          startWidth: state.hud.width
        };
        dragState = null;
        if (isPointer && resizeGrip.setPointerCapture) {
          try { resizeGrip.setPointerCapture(ev.pointerId); } catch (_) {}
        }
      };
      resizeGrip.addEventListener('pointerdown', startResize, { passive: false });
      resizeGrip.addEventListener('mousedown', startResize);
    }

    hud.addEventListener('click', (ev) => {
      const ctl = ev.target.closest('[data-hud-action]');
      if (ctl) {
        ev.preventDefault();
        const action = ctl.dataset.hudAction;
        if (action === 'collapse') {
          state.hud.collapsed = !state.hud.collapsed;
          saveHUDState();
          renderHud(state.data || {});
        } else if (action === 'reset') {
          state.hud = { ...(HUD_DEFAULTS || {}) };
          saveHUDState();
          renderHud(state.data || {});
        } else if (action === 'edit') {
          state.hudEditSnapshot = JSON.parse(JSON.stringify(state.hud || HUD_DEFAULTS));
          state.hudEditing = true;
          state.hud.hidden = false;
          state.hud.collapsed = false;
          renderHud(state.data || {});
        } else if (action === 'resetDraft') {
          state.hud = { ...(HUD_DEFAULTS || {}) };
          renderHud(state.data || {});
        } else if (action === 'nudgeLeft') {
          state.hud.left = (state.hud.left || HUD_DEFAULTS.left) - 20;
          applyHUDBounds();
        } else if (action === 'nudgeRight') {
          state.hud.left = (state.hud.left || HUD_DEFAULTS.left) + 20;
          applyHUDBounds();
        } else if (action === 'nudgeUp') {
          state.hud.top = (state.hud.top || HUD_DEFAULTS.top) - 20;
          applyHUDBounds();
        } else if (action === 'nudgeDown') {
          state.hud.top = (state.hud.top || HUD_DEFAULTS.top) + 20;
          applyHUDBounds();
        } else if (action === 'sizeUp') {
          state.hud.width = (state.hud.width || HUD_DEFAULTS.width) + 40;
          applyHUDBounds();
        } else if (action === 'sizeDown') {
          state.hud.width = (state.hud.width || HUD_DEFAULTS.width) - 40;
          applyHUDBounds();
        } else if (action === 'cancel') {
          if (state.hudEditSnapshot) state.hud = JSON.parse(JSON.stringify(state.hudEditSnapshot));
          state.hudEditing = false;
          state.hudEditSnapshot = null;
          saveHUDState();
          renderHud(state.data || {});
          send('simHudEditor', { action: 'cancel' });
        } else if (action === 'save') {
          state.hudEditing = false;
          state.hudEditSnapshot = null;
          saveHUDState();
          renderHud(state.data || {});
          send('simHudEditor', { action: 'save' });
        }
        return;
      }
      const modelAction = ev.target.closest('[data-action]');
      if (modelAction) {
        ev.preventDefault();
        send('simAction', {
          action: modelAction.dataset.action,
          section: state.section
        });
      }
    });
  }

  function sectionButton(id, label, desc) {
    const active = state.section === id ? ' active' : '';
    return `<button class="sim-nav-btn${active}" data-section="${id}">${esc(label)}<small>${esc(desc)}</small></button>`;
  }

  function card(title, body, actions) {
    return `
      <div class="sim-card">
        <h4>${esc(title)}</h4>
        ${body || ''}
        ${actions ? `<div class="sim-actions">${actions}</div>` : ''}
      </div>
    `;
  }

  function btn(label, action, kind, id) {
    return `<button class="sim-btn${kind ? ' ' + kind : ''}" data-action="${esc(action)}"${id ? ` data-id="${esc(id)}"` : ''}>${esc(label)}</button>`;
  }

  function renderOverview(data) {
    const shift = data.shift;
    const incident = data.incident;
    const dispatch = Array.isArray(data.dispatch) ? data.dispatch.slice(0, 3) : [];
    const bolos = Array.isArray(data.bolos) ? data.bolos.slice(0, 3) : [];
    return `
      <div>
        <div class="sim-section-title">Overview</div>
        <div class="sim-section-sub">Fast actions without the menu kicking you back out.</div>
      </div>
      <div class="sim-note">Recommended next action: <span class="sim-strong">${esc(data.recommendedAction || 'Open or claim a scene.')}</span></div>
      <div class="sim-grid">
        ${card('Shift', `<div class="sim-meta">${shift ? `<span class="sim-strong">${esc(shift.callsign || 'UNIT')}</span><br>Status: ${esc(shift.status || '10-7')}<br>Zone: ${esc(shift.zone || 'General Patrol')}<br>Goal: ${esc(shift.patrolGoal || 'Patrol')}` : 'No active shift.'}</div>`, shift ? `${btn('Change Status', 'changeStatus', 'primary')}${btn('End Shift', 'endShift')}` : `${btn('Start Shift', 'startShift', 'primary')}`)}
        ${card('Active Scene', `<div class="sim-meta">${incident ? `<span class="sim-strong">${esc(incident.id || 'Scene')}</span><br>Type: ${esc(incident.incidentType || 'Unknown')}<br>Status: ${esc(incident.status || 'pending')}<br>Target: ${esc(incident.context && incident.context.subjectLabel || 'Unknown')}` : 'No active scene right now.'}</div>`, incident ? `${btn('Scene Tools', 'refreshState', 'primary')}` : `${btn('Open Ped Scene', 'openPedScene', 'primary')}${btn('Open Vehicle Scene', 'openVehicleScene')}`)}
      </div>
      ${card('Dispatch Snapshot', dispatch.length ? `<div class="sim-list">${dispatch.map(call => `
        <div class="sim-list-item">
          <div class="sim-list-head"><span>${esc(call.id || 'CALL')} • ${esc(call.title || 'Dispatch')}</span><span class="sim-badge">P${esc(call.priority || 3)}</span></div>
          <div class="sim-meta">${esc(trim(call.callerUpdate || call.zone || '', 110))}</div>
          <div class="sim-actions">${btn('Claim Secondary', 'claimDispatch', '', call.id)}${btn('Open as Scene', 'openDispatchScene', 'primary', call.id)}</div>
        </div>`).join('')}</div>` : `<div class="sim-empty">No active dispatch calls.</div>`, `${btn('Panic / Emergency Traffic', 'panic', 'warn')}${btn('Add BOLO / APB', 'addBolo', 'primary')}`)}
      ${card('BOLO / APB Board', bolos.length ? `<div class="sim-list">${bolos.map(b => `<div class="sim-list-item"><div class="sim-list-head"><span>${esc(b.id || 'BOLO')} • ${esc(b.label || 'BOLO')}</span><span class="sim-badge">${esc(b.category || 'General')}</span></div><div class="sim-meta">${esc(trim(b.reason || '', 110))}</div><div class="sim-actions">${btn('Clear', 'clearBolo', '', b.id)}</div></div>`).join('')}</div>` : `<div class="sim-empty">No active BOLOs.</div>`)}
    `;
  }

  function renderShift(data) {
    const shift = data.shift;
    return `
      <div><div class="sim-section-title">Shift / Duty</div><div class="sim-section-sub">Start, update, or end your patrol shift.</div></div>
      ${card('Shift Status', `<div class="sim-grid-3">
        <div class="sim-pill"><div class="sim-pill-label">Callsign</div><div class="sim-pill-value">${esc(shift && shift.callsign || 'Not Started')}</div></div>
        <div class="sim-pill"><div class="sim-pill-label">Status</div><div class="sim-pill-value">${esc(shift && shift.status || '10-7')}</div></div>
        <div class="sim-pill"><div class="sim-pill-label">Zone</div><div class="sim-pill-value">${esc(shift && shift.zone || 'General Patrol')}</div></div>
      </div>`, shift ? `${btn('Change Status', 'changeStatus', 'primary')}${btn('End Shift', 'endShift')}` : `${btn('Start Shift', 'startShift', 'primary')}`)}
    `;
  }

  function renderDispatch(data) {
    const dispatch = Array.isArray(data.dispatch) ? data.dispatch : [];
    const bolos = Array.isArray(data.bolos) ? data.bolos : [];
    return `
      <div><div class="sim-section-title">Dispatch / BOLO / Radio</div><div class="sim-section-sub">Claim calls, open scenes, issue BOLOs, and trigger emergency traffic.</div></div>
      ${card('Quick Actions', `<div class="sim-meta">Keep dispatch actions inside this panel without bouncing back to the top menu.</div>`, `${btn('Panic / Emergency Traffic', 'panic', 'warn')}${btn('Add BOLO / APB', 'addBolo', 'primary')}${btn('Refresh State', 'refreshState')}`)}
      ${card('Active Dispatch Calls', dispatch.length ? `<div class="sim-list">${dispatch.map(call => `<div class="sim-list-item"><div class="sim-list-head"><span>${esc(call.id || 'CALL')} • ${esc(call.title || 'Dispatch')}</span><span class="sim-badge">P${esc(call.priority || 3)}</span></div><div class="sim-meta">${esc(trim(call.callerUpdate || '', 130))}<br>${esc(call.zone || 'Unknown zone')}</div><div class="sim-actions">${btn('Claim Secondary', 'claimDispatch', '', call.id)}${btn('Open as Primary', 'openDispatchScene', 'primary', call.id)}</div></div>`).join('')}</div>` : `<div class="sim-empty">No active dispatch calls.</div>`)}
      ${card('BOLO / APB Board', bolos.length ? `<div class="sim-list">${bolos.map(b => `<div class="sim-list-item"><div class="sim-list-head"><span>${esc(b.id || 'BOLO')} • ${esc(b.label || 'BOLO')}</span><span class="sim-badge">${esc(b.category || 'General')}</span></div><div class="sim-meta">${esc(trim(b.reason || '', 120))}</div><div class="sim-actions">${btn('Clear BOLO', 'clearBolo', '', b.id)}</div></div>`).join('')}</div>` : `<div class="sim-empty">No active BOLOs.</div>`)}
    `;
  }

  function renderScene(data) {
    const incident = data.incident;
    if (!incident) {
      return `
        <div><div class="sim-section-title">Scene / Incident Tools</div><div class="sim-section-sub">Open a scene from a nearby ped or vehicle.</div></div>
        ${card('No Active Scene', `<div class="sim-meta">Face a nearby ped or vehicle, then open a new scene from here.</div>`, `${btn('Open Nearby Ped Scene', 'openPedScene', 'primary')}${btn('Open Nearby Vehicle Scene', 'openVehicleScene')}`)}
      `;
    }
    const roleText = Array.isArray(incident.roles) && incident.roles.length
      ? incident.roles.map(unit => `${unit.callsign || unit.name || 'Unit'} (${unit.role || 'unit'})`).join(', ')
      : 'No attached units yet';
    return `
      <div><div class="sim-section-title">Scene / Incident Tools</div><div class="sim-section-sub">Primary / secondary roles, notes, witnesses, backup, and closeout.</div></div>
      ${card(`Scene ${incident.id || ''}`, `<div class="sim-meta">Type: <span class="sim-strong">${esc(incident.incidentType || 'Unknown')}</span><br>Status: ${esc(incident.status || 'pending')}<br>Priority: ${esc(incident.priority || 3)}<br>Units: ${esc(roleText)}<br>Location: ${esc(trim(incident.context && incident.context.street || incident.context && incident.context.areaLabel || 'Unknown', 120))}</div>`, `${btn('Set Status', 'setSceneStatus', 'primary')}${btn('Safe / Unsafe Flags', 'sceneFlags')}${btn('Attach Role', 'attachRole')}`)}
      ${card('Scene Documentation', `<div class="sim-meta">Shared note, witness statement, observation, K9, and backup tools.</div>`, `${btn('Shared Note', 'sharedNote', 'primary')}${btn('Witness', 'witness')}${btn('Observation', 'observation')}${btn('Request Backup', 'backup')}${btn('K9 Request', 'k9')}`)}
      ${card('Closeout', `<div class="sim-meta">Checklist, narrative summary, and final scene closeout.</div>`, `${btn('Scene Checklist', 'sceneChecklist')}${btn('Generate Summary', 'generateSummary')}${btn('Close Scene', 'closeScene', 'warn')}`)}
    `;
  }

  function renderStops(data) {
    const incident = data.incident;
    if (!incident) {
      return `
        <div><div class="sim-section-title">Traffic Stop / Contact Workflow</div><div class="sim-section-sub">Open a stop scene first.</div></div>
        <div class="sim-empty">No active stop or contact scene.</div>
      `;
    }
    return `
      <div><div class="sim-section-title">Traffic Stop / Contact Workflow</div><div class="sim-section-sub">Reason, returns, DUI, legal basis, evidence, and tow flow.</div></div>
      ${card('Stop Summary', `<div class="sim-meta">Target: <span class="sim-strong">${esc(incident.context && incident.context.subjectLabel || 'Unknown')}</span><br>Plate: ${esc(incident.context && incident.context.plate || 'N/A')}<br>Demeanor: ${esc(incident.suspect && incident.suspect.demeanor || 'Unknown')}<br>ID Outcome: ${esc(incident.stop && incident.stop.idOutcome || 'pending')}<br>Search Mode: ${esc(incident.search && incident.search.mode || 'none')}</div>`)}
      ${card('Core Stop Actions', `<div class="sim-meta">Record the reason, run returns, and document interview cues.</div>`, `${btn('Reason for Stop', 'recordReason', 'primary')}${btn('Vehicle Return / VIN', 'vehicleCheck')}${btn('ID / License Check', 'idCheck')}${btn('Interview Prompt', 'interview')}${btn('Observed Cue', 'cue')}${btn('DUI Workflow', 'dui')}`)}
      ${card('Legal Basis / Evidence', `<div class="sim-meta">Document consent or probable cause before searching.</div>`, `${btn('Search Decision', 'searchDecision', 'primary')}${btn('Probable Cause', 'probableCause')}${btn('Plain View / Evidence', 'plainViewEvidence')}${btn('Felony / Tow / Transport', 'felonyTow')}${btn('Behavior / De-escalation', 'behaviorAction')}${btn('Stop Checklist', 'stopChecklist')}`)}
    `;
  }

  function renderReports(data) {
    const recent = Array.isArray(data.recent) ? data.recent : [];
    return `
      <div><div class="sim-section-title">Reports / Court / Detective</div><div class="sim-section-sub">Charges, warrant flow, report preview, and follow-up case reopen.</div></div>
      ${card('Report Tools', `<div class="sim-meta">Build out your report with generated details and court workflow.</div>`, `${btn('Add Charge', 'addCharge', 'primary')}${btn('Auto Recommend Charges', 'autoCharges')}${btn('Request Warrant', 'requestWarrant')}${btn('Generate Report Preview', 'reportPreview')}`)}
      ${card('Recent Scenes', recent.length ? `<div class="sim-list">${recent.map(item => `<div class="sim-list-item"><div class="sim-list-head"><span>${esc(item.id || 'Scene')}</span><span class="sim-badge">${esc(item.status || item.type || 'recent')}</span></div><div class="sim-meta">${esc(trim(item.type || '', 40))}${item.score ? `<br>Score: ${esc(item.score.total || '?')} (${esc(item.score.rating || '')})` : ''}</div><div class="sim-actions">${btn('Reopen', 'reopenIncident', 'primary', item.id)}</div></div>`).join('')}</div>` : `<div class="sim-empty">No recent scenes yet.</div>`)}
    `;
  }

  function renderTraining(data) {
    const shift = data.shift || {};
    const weekly = data.weekly || {};
    return `
      <div><div class="sim-section-title">Training / Scorecards</div><div class="sim-section-sub">Academy scenarios and weekly performance snapshots.</div></div>
      ${card('Performance', `<div class="sim-grid-3"><div class="sim-pill"><div class="sim-pill-label">Shift Incidents</div><div class="sim-pill-value">${esc(shift.stats && shift.stats.incidents || 0)}</div></div><div class="sim-pill"><div class="sim-pill-label">Average Score</div><div class="sim-pill-value">${esc(Number(shift.stats && shift.stats.averageScore || 0).toFixed(1))}</div></div><div class="sim-pill"><div class="sim-pill-label">Weekly Reviews</div><div class="sim-pill-value">${esc(weekly.reviews || 0)}</div></div></div>`, `${btn('Start Training Scenario', 'startTraining', 'primary')}`)}
    `;
  }

  function renderPolicy() {
    return `
      <div><div class="sim-section-title">Policy / IA / Commendations</div><div class="sim-section-sub">Supervisor notes, complaints, commendations, and review actions.</div></div>
      ${card('Policy Actions', `<div class="sim-meta">Use this for commendations, complaints, force review, or supervisor coaching notes.</div>`, `${btn('Supervisor / IA Action', 'policyAction', 'primary')}`)}
    `;
  }

  function renderHud(data) {
    const hud = document.getElementById(HUD_ID);
    if (hud) {
      hud.classList.remove('open');
      hud.style.display = 'none';
      hud.innerHTML = '';
    }
  }

  function render() {

    const shell = injectShell();
    if (!state.open) {
      shell.classList.remove('open');
      applyHUDBounds();
      return;
    }
    shell.classList.add('open');
    applyUIBounds();

    const data = state.data || {};
    renderHud(data);
    applyHUDBounds();
    const shift = data.shift || null;
    const incident = data.incident || null;
    const dispatch = Array.isArray(data.dispatch) ? data.dispatch.length : 0;

    const boloCount = Array.isArray(data.bolos) ? data.bolos.length : 0;
    const nextAction = esc(data.recommendedAction || 'Open or claim a dispatch call.');
    document.getElementById('sim-statusbar').innerHTML = `
      <div class="sim-pill"><div class="sim-pill-label">Unit / Status</div><div class="sim-pill-value">${esc(shift && shift.callsign || 'UNIT')} • ${esc(shift && shift.status || '10-7')}</div></div>
      <div class="sim-pill"><div class="sim-pill-label">Active Scene</div><div class="sim-pill-value">${esc(incident && incident.id || 'None')}</div></div>
      <div class="sim-pill"><div class="sim-pill-label">Dispatch / BOLO</div><div class="sim-pill-value">${esc(dispatch)} Calls • ${esc(boloCount)} BOLOs</div></div>
      <div class="sim-pill"><div class="sim-pill-label">Recommended Next Step</div><div class="sim-pill-value">${nextAction}</div></div>
    `;

    document.getElementById('sim-nav').innerHTML = [
      sectionButton('overview', 'Overview', 'Quick status and actions'),
      sectionButton('shift', 'Shift / Duty', 'Callsign, zone, status'),
      sectionButton('dispatch', 'Dispatch / BOLO', 'Calls, APBs, panic'),
      sectionButton('scene', 'Scene Tools', 'Scene roles and notes'),
      sectionButton('stops', 'Traffic Stops', 'Returns, DUI, search'),
      sectionButton('reports', 'Reports / Court', 'Charges and warrants'),
      sectionButton('training', 'Training', 'Scenarios and scorecards'),
      sectionButton('policy', 'Policy / IA', 'Reviews and commendations')
    ].join('');

    let html = '';
    switch (state.section) {
      case 'shift': html = renderShift(data); break;
      case 'dispatch': html = renderDispatch(data); break;
      case 'scene': html = renderScene(data); break;
      case 'stops': html = renderStops(data); break;
      case 'reports': html = renderReports(data); break;
      case 'training': html = renderTraining(data); break;
      case 'policy': html = renderPolicy(data); break;
      default: html = renderOverview(data); break;
    }
    document.getElementById('sim-content').innerHTML = html;
  }

  loadUIState();
  loadHUDState();
  fitUIToViewport();
  fitHUDToViewport();
  injectStyle();
  injectShell();
  injectHud();

  window.addEventListener('resize', () => {
    fitUIToViewport();
    fitHUDToViewport();
    applyUIBounds();
    applyHUDBounds();
    saveUIState();
    saveHUDState();
  });

  window.addEventListener('message', (event) => {
    const d = event.data || {};
    if (d.action === 'sim:open') {
      state.open = true;
      const payload = d.payload || {};
      state.data = payload;
      if (payload.section) state.section = payload.section;
      render();
    } else if (d.action === 'sim:update') {
      const payload = d.payload || {};
      state.data = payload;
      if (payload.section) state.section = state.section || payload.section;
      render();
    } else if (d.action === 'sim:close') {
      state.open = false;
      render();
    } else if (d.action === 'sim:hud' || d.action === 'sim:hudControl') {
      renderHud({});
    }
  });

  window.addEventListener('keydown', (e) => {
    if (state.hudEditing === true) {
      const step = e.shiftKey ? 40 : 12;
      if (e.key === 'ArrowLeft') { e.preventDefault(); state.hud.left -= step; applyHUDBounds(); return; }
      if (e.key === 'ArrowRight') { e.preventDefault(); state.hud.left += step; applyHUDBounds(); return; }
      if (e.key === 'ArrowUp') { e.preventDefault(); state.hud.top -= step; applyHUDBounds(); return; }
      if (e.key === 'ArrowDown') { e.preventDefault(); state.hud.top += step; applyHUDBounds(); return; }
      if (e.key === '+' || e.key === '=') { e.preventDefault(); state.hud.width += 40; applyHUDBounds(); return; }
      if (e.key === '-' || e.key === '_') { e.preventDefault(); state.hud.width -= 40; applyHUDBounds(); return; }
    }
    if (state.hudEditing === true && e.key === 'Escape') {
      e.preventDefault();
      e.stopImmediatePropagation();
      if (state.hudEditSnapshot) state.hud = JSON.parse(JSON.stringify(state.hudEditSnapshot));
      state.hudEditing = false;
      state.hudEditSnapshot = null;
      saveHUDState();
      renderHud(state.data || {});
      send('simHudEditor', { action: 'cancel' });
      return;
    }
    if (!state.open) return;
    if (e.key === 'Escape') {
      e.preventDefault();
      e.stopImmediatePropagation();
      send('simClose', {});
    }
  }, true);
})();

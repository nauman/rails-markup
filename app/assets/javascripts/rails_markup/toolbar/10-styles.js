  Object.assign(RailsMarkupToolbar, {
    _injectStyles() {
      if (document.getElementById("rm-toolbar-styles")) return;
      const style = document.createElement("style");
      style.id = "rm-toolbar-styles";
      style.textContent = `
        @keyframes rm-pulse { 0%,100%{box-shadow:0 2px 8px rgba(0,0,0,0.2)} 50%{box-shadow:0 2px 12px rgba(0,0,0,0.3),0 0 0 4px rgba(99,102,241,0.15)} }
        @keyframes rm-toast-in { from{opacity:0;transform:translateY(16px) scale(0.95)} to{opacity:1;transform:translateY(0) scale(1)} }
        @keyframes rm-toast-out { from{opacity:1;transform:translateY(0) scale(1)} to{opacity:0;transform:translateY(16px) scale(0.95)} }
        #rm-toolbar-root { position:fixed; inset:0; pointer-events:none; z-index:9979; }
        #rm-toolbar-root * { box-sizing:border-box; font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,"Helvetica Neue",sans-serif; }
        #rm-toolbar-root .rm-dock, #rm-toolbar-root .rm-panel, #rm-toolbar-root .rm-popup { pointer-events:auto; }
        #rm-toolbar-root .rm-dock { position:fixed; z-index:9980; display:flex; align-items:center; padding:4px; border:1px solid var(--rm-accent-hover); border-radius:14px; background:var(--rm-accent); color:#fff; box-shadow:0 6px 20px #0003,0 1px 3px #0002; }
        #rm-toolbar-root .rm-dock button { position:static; display:flex; align-items:center; justify-content:center; gap:6px; flex-shrink:0; min-width:var(--rm-control-size); height:var(--rm-control-size); margin:0; padding:0 10px; border:0; border-radius:10px; background:transparent; color:#e5e7eb; cursor:pointer; box-shadow:none; appearance:none; transition:background .15s,color .15s; }
        #rm-toolbar-root .rm-dock button:hover { background:#ffffff18; color:#fff; }
        #rm-toolbar-root .rm-dock button:focus-visible { outline:2px solid #fff; outline-offset:2px; }
        #rm-toolbar-root .rm-dock button.rm-fab { background:var(--rm-accent); color:#fff; }
        #rm-toolbar-root .rm-dock button.rm-fab:hover { background:var(--rm-accent-hover); }
        #rm-toolbar-root .rm-dock[data-state="annotating"] button.rm-fab { box-shadow:inset 0 0 0 2px #ffffff80; }
        #rm-toolbar-root .rm-dock svg { width:18px; height:18px; fill:none; stroke:currentColor; stroke-width:1.8; stroke-linecap:round; stroke-linejoin:round; }
        #rm-toolbar-root .rm-dock-controls { display:flex; align-items:center; gap:2px; margin-left:4px; padding-left:4px; border-left:1px solid #ffffff26; }
        #rm-toolbar-root .rm-dock-controls[hidden] { display:none; }
        #rm-toolbar-root .rm-panel-toggle { order:0; }
        #rm-toolbar-root .rm-toolbar-settings { order:1; }
        #rm-toolbar-root .rm-dock-close { order:2; }
        #rm-toolbar-root .rm-panel-toggle-badge { font-size:11px; font-weight:600; font-variant-numeric:tabular-nums; color:#e5e7eb; }
        @media (prefers-reduced-motion:reduce) { #rm-toolbar-root .rm-dock button { transition:none; } }
        #rm-toolbar-root .rm-toast-container { position:fixed; z-index:9983; display:flex; flex-direction:column; gap:8px; pointer-events:none; }
        #rm-pins-container { position:absolute; top:0; left:0; width:100%; z-index:9979; pointer-events:none; }
        #rm-pins-container .rm-pin { pointer-events:auto; }
        #rm-toolbar-root .rm-popup { max-height:calc(100vh - 24px); overflow-y:auto; display:none; position:fixed; z-index:9982; width:360px; max-width:calc(100vw - 24px); background:#fff; border-radius:16px; box-shadow:0 18px 48px #18213824,0 2px 6px #1821380a; border:1px solid #dce1e8; padding:16px; }
        #rm-toolbar-root .rm-popup textarea { display:block; width:100%; max-width:100%; font-size:13px; font-weight:400; line-height:1.4; color:#1f2937; height:auto; margin:0; border:1px solid #e5e7eb; border-radius:12px; padding:12px; resize:none; outline:none; font-family:inherit; background:#fff; background-image:none; box-shadow:none; appearance:none; -webkit-appearance:none; transition:border-color 0.15s,box-shadow 0.15s; }
        #rm-toolbar-root .rm-popup textarea:focus { border:1px solid #818cf8; box-shadow:0 0 0 3px rgba(99,102,241,0.1); }
        #rm-toolbar-root .rm-menu { position:relative; display:inline-block; vertical-align:middle; }
        #rm-toolbar-root .rm-menu-btn { min-height:32px; display:inline-flex; align-items:center; gap:4px; width:auto; height:auto; margin:0; font-size:11px; font-weight:500; line-height:1.4; color:#374151; border:1px solid #e5e7eb; border-radius:8px; padding:6px 8px; background:#fff; background-image:none; box-shadow:none; outline:none; text-transform:none; appearance:none; -webkit-appearance:none; cursor:pointer; }
        #rm-toolbar-root .rm-menu-btn:hover { border-color:#d1d5db; background:#fff; }
        #rm-toolbar-root .rm-menu-btn:focus { outline:none; border-color:#818cf8; box-shadow:0 0 0 3px rgba(99,102,241,0.1); }
        #rm-toolbar-root .rm-menu-btn[aria-expanded="true"] { border-color:#818cf8; }
        #rm-toolbar-root .rm-menu-chevron { width:10px; height:10px; flex-shrink:0; fill:none; stroke:currentColor; stroke-width:2; stroke-linecap:round; stroke-linejoin:round; opacity:0.55; }
        #rm-toolbar-root .rm-menu-list { display:none; position:absolute; top:calc(100% + 4px); left:0; z-index:9984; min-width:100%; padding:4px; margin:0; list-style:none; background:#fff; border:1px solid #e5e7eb; border-radius:10px; box-shadow:0 10px 24px rgba(0,0,0,0.12); }
        #rm-toolbar-root .rm-menu-list.rm-menu-open { display:block; }
        #rm-toolbar-root .rm-menu-option { min-height:32px; display:block; width:100%; margin:0; padding:6px 10px; font-size:11px; font-weight:500; line-height:1.4; color:#374151; text-align:left; border:none; border-radius:6px; background:transparent; background-image:none; box-shadow:none; cursor:pointer; appearance:none; -webkit-appearance:none; }
        #rm-toolbar-root .rm-menu-option:hover, #rm-toolbar-root .rm-menu-option:focus { background:#f3f4f6; outline:none; }
        #rm-toolbar-root .rm-menu-option-active { background:#eef2ff; color:#4338ca; }
        #rm-toolbar-root .rm-menu-compact .rm-menu-btn { font-size:11px; min-height:28px; padding:4px 7px; border-radius:4px; color:#6b7280; }
        #rm-toolbar-root .rm-menu-compact .rm-menu-list, #rm-toolbar-root .rm-menu-list-compact { min-width:120px; right:0; left:auto; }
        #rm-toolbar-root .rm-menu-compact .rm-menu-option, #rm-toolbar-root .rm-menu-list-compact .rm-menu-option { font-size:10px; padding:5px 8px; }
        #rm-toolbar-root .rm-popup-el { font-size:11px; color:#596579; font-family:monospace; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; line-height:1.4; }
        #rm-toolbar-root .rm-popup-text { font-size:12px; color:#6b7280; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; margin-top:2px; line-height:1.4; }
        #rm-toolbar-root .rm-popup-actions { display:flex; justify-content:flex-end; align-items:center; gap:8px; margin-top:8px; }
        #rm-toolbar-root .rm-popup-actions .rm-count { font-size:11px; color:#596579; margin-left:auto; font-variant-numeric:tabular-nums; }
        #rm-toolbar-root .rm-btn-cancel { min-height:36px; padding:8px 12px; font-size:12px; color:#596579; background:none; background-image:none; border:none; box-shadow:none; cursor:pointer; border-radius:8px; appearance:none; -webkit-appearance:none; }
        #rm-toolbar-root .rm-btn-cancel:hover { color:#6b7280; }
        #rm-toolbar-root .rm-btn-submit { min-height:36px; padding:8px 16px; font-size:12px; font-weight:500; color:#fff; border:none; border-radius:8px; cursor:pointer; display:inline-flex; align-items:center; gap:6px; box-shadow:none; appearance:none; -webkit-appearance:none; }
        #rm-toolbar-root .rm-btn-submit kbd { font-size:9px; opacity:0.6; font-family:sans-serif; }
        #rm-toolbar-root .rm-panel { display:none; position:fixed; z-index:9981; width:380px; max-width:calc(100vw - 48px); max-height: min(560px, calc(100vh - 100px)); overflow:hidden; background:#fff; border-radius:16px; box-shadow:0 18px 48px #18213824,0 2px 6px #1821380a; border:1px solid #dce1e8; flex-direction:column; }
        #rm-toolbar-root .rm-panel-header { display:flex; align-items:center; justify-content:space-between; padding:16px; border-bottom:1px solid #e5e7eb; }
        #rm-toolbar-root .rm-panel-header h3 { margin:0; font-size:15px; font-weight:600; color:#1f2937; }
        #rm-toolbar-root .rm-panel-header-actions { display:flex; align-items:center; gap:6px; }
        #rm-toolbar-root .rm-panel-count { min-width:20px; text-align:center; padding:2px 6px; font-size:10px; font-weight:600; border-radius:10px; }
        #rm-toolbar-root .rm-settings { padding:16px; overflow-y:auto; }
        #rm-toolbar-root .rm-settings[hidden] { display:none; }
        #rm-toolbar-root .rm-image-options { margin:8px 0; }
        #rm-toolbar-root .rm-image-options:not([open]) > :not(summary) { display:none; }
        #rm-toolbar-root .rm-image-options[hidden] { display:none; }
        #rm-toolbar-root .rm-image-options > summary { cursor:pointer;color:#64748b;font-size:12px;padding:5px 0; }
        #rm-toolbar-root .rm-screenshot-actions { display:flex;flex-wrap:wrap;gap:8px;margin:12px 0; }
        #rm-toolbar-root .rm-screenshot-actions[hidden], #rm-toolbar-root .rm-screenshot-actions [hidden] { display:none; }
        #rm-toolbar-root .rm-screenshot-actions button { border:1px solid #dce1e8;border-radius:7px;padding:7px 10px;background:#fff;color:#334155;font-size:12px;cursor:pointer; }
        #rm-toolbar-root .rm-drawing-tools button { border:1px solid #dce1e8;border-radius:7px;background:#fff;color:#334155;cursor:pointer; }
        #rm-toolbar-root .rm-screenshot-actions span { flex-basis:100%;font-size:11px;line-height:1.5;color:#596579; }

        #rm-toolbar-root .rm-panel[data-view="settings"] .rm-panel-count,
        #rm-toolbar-root .rm-panel[data-view="settings"] .rm-filter-chips,
        #rm-toolbar-root .rm-panel[data-view="settings"] .rm-panel-list,
        #rm-toolbar-root .rm-panel[data-view="settings"] .rm-panel-footer { display:none; }
        #rm-toolbar-root .rm-setting-choice { border:1px solid #e2e6ec; border-radius:8px; padding:9px 12px; background:#fff; color:#475569; font-size:12px; cursor:pointer; }
        #rm-toolbar-root .rm-setting-choice[aria-pressed="true"] { background:#eef1f5; border-color:#8995a5; color:#172033; box-shadow:inset 0 0 0 1px #8995a5; }
        #rm-toolbar-root .rm-color-swatch { width:36px; height:36px; padding:0; border:3px solid #fff; border-radius:50%; color:#fff; font-size:17px; }
        #rm-toolbar-root .rm-color-swatch[aria-pressed="true"] { color:#fff; box-shadow:0 0 0 2px #64748b; border-color:#fff; }
        #rm-toolbar-root .rm-corner-choice { font-size:24px; width:54px; padding:4px; }
        #rm-toolbar-root .rm-settings-group.rm-settings-switch-row { flex-direction:row; align-items:center; justify-content:space-between; padding-top:16px; border-top:1px solid #eef1f5; }
        #rm-toolbar-root .rm-setting-switch { width:38px; height:22px; padding:3px; border:0; border-radius:20px; background:#94a3b8; cursor:pointer; }
        #rm-toolbar-root .rm-setting-switch span { display:block; width:16px; height:16px; background:#fff; border-radius:50%; }
        #rm-toolbar-root .rm-setting-switch[aria-checked="true"] { background:#475569; }
        #rm-toolbar-root .rm-setting-switch[aria-checked="true"] span { transform:translateX(16px); }
        #rm-toolbar-root .rm-setting-choice:focus-visible, #rm-toolbar-root .rm-setting-switch:focus-visible { outline:2px solid #475569; outline-offset:3px; }

        #rm-toolbar-root .rm-settings-group { display:flex; flex-direction:column; gap:8px; margin-bottom:14px; }
        #rm-toolbar-root .rm-settings-label { font-size:12px; font-weight:600; color:#516074; }
        #rm-toolbar-root .rm-settings-options { display:flex; flex-wrap:wrap; gap:6px; }
        #rm-toolbar-root .rm-panel-close { min-width:32px; min-height:32px; padding:8px; color:#596579; background:none; border:none; cursor:pointer; border-radius:8px; }
        #rm-toolbar-root .rm-panel-close:hover { color:#6b7280; }
        #rm-toolbar-root .rm-panel-close svg { width:16px; height:16px; fill:none; stroke:currentColor; stroke-width:2; stroke-linecap:round; stroke-linejoin:round; }
        #rm-toolbar-root .rm-filter-chips { display:flex; gap:6px; padding:10px 16px; border-bottom:1px solid #f9fafb; }
        #rm-toolbar-root .rm-chip { min-height:32px; padding:6px 10px; font-size:12px; font-weight:500; border-radius:10px; cursor:pointer; transition:all 0.15s; border:none; }
        #rm-toolbar-root .rm-chip-active { color:#fff; }
        #rm-toolbar-root .rm-chip-inactive { background:#f9fafb; color:#596579; }
        #rm-toolbar-root .rm-chip-inactive:hover { color:#6b7280; }
        #rm-toolbar-root .rm-panel-list { flex:1; min-height:0; overflow-y:auto; padding:12px; display:flex; flex-direction:column; gap:8px; }
        #rm-toolbar-root .rm-panel-footer { display:flex; align-items:center; gap:8px; padding:10px 16px; border-top:1px solid #f3f4f6; font-size:11px; color:#596579; }
        #rm-toolbar-root .rm-status-dot { width:8px; height:8px; border-radius:50%; background:#d1d5db; }
        #rm-toolbar-root .rm-card { padding:12px; background:#fff; border-radius:8px; border:1px solid #e5e7eb; border-left:3px solid; cursor:pointer; transition:all 0.15s; }
        #rm-toolbar-root .rm-card:hover { box-shadow:0 2px 8px rgba(0,0,0,0.05); }
        #rm-toolbar-root .rm-card-top { display:flex; align-items:center; gap:6px; flex-wrap:wrap; }
        #rm-toolbar-root .rm-card-dot { width:8px; height:8px; border-radius:50%; flex-shrink:0; }
        #rm-toolbar-root .rm-card-id { font-size:10px; font-weight:600; color:#596579; }
        #rm-toolbar-root .rm-card-badge { padding:2px 6px; font-size:10px; font-weight:500; border-radius:10px; }
        #rm-toolbar-root .rm-card-body { margin-top:6px; font-size:13px; line-height:1.5; color:#1f2937; }
        #rm-toolbar-root .rm-card-path { margin-top:4px; font-size:11px; color:#596579; font-family:monospace; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }
        #rm-toolbar-root .rm-card-thread { margin-top:8px; padding:8px; background:rgba(249,250,251,0.8); border-radius:8px; font-size:12px; color:#6b7280; border-left:2px solid; }
        #rm-toolbar-root .rm-card-thread-role { font-size:11px; font-weight:600; color:#596579; }
        #rm-toolbar-root .rm-empty { text-align:center; padding:32px 16px; color:#596579; }
        #rm-toolbar-root .rm-empty-icon { font-size:32px; margin-bottom:8px; }
        #rm-toolbar-root .rm-empty-text { font-size:13px; }
        #rm-pins-container .rm-pin { position:absolute; display:flex; align-items:center; justify-content:center; width:20px; height:20px; border-radius:50%; color:#fff; font-size:10px; font-weight:700; cursor:pointer; transition:transform 0.2s; z-index:9979; box-shadow:0 2px 8px rgba(0,0,0,0.2); }
        #rm-pins-container .rm-pin:hover { transform:scale(1.25); }
        #rm-pins-container .rm-pin-active { animation:rm-pulse 2s ease-in-out infinite; }
        #rm-toolbar-root .rm-toast { padding:8px 12px; border-radius:8px; border:1px solid; font-size:12px; font-weight:500; box-shadow:0 2px 8px rgba(0,0,0,0.05); animation:rm-toast-in 0.3s ease; }
        #rm-toolbar-root button, #rm-toolbar-root textarea { font-family:inherit; text-transform:none; letter-spacing:normal; }
        #rm-toolbar-root button:focus-visible { outline:2px solid #6366f1; outline-offset:2px; }
        #rm-toolbar-root .rm-popup-heading { margin:0 0 12px; color:#25272d; font-size:15px; font-weight:650; line-height:1.4; }
        #rm-toolbar-root .rm-popup-el { color:#516074; }
        #rm-toolbar-root #rm-char-count { margin-left:auto; color:#596579; font-size:11px; font-variant-numeric:tabular-nums; }
        #rm-pins-container .rm-pin { font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif; }
        #rm-toolbar-root .rm-card-body { overflow-wrap:anywhere; }
        #rm-toolbar-root .rm-popup textarea { line-height:1.6; border-radius:8px; }
        #rm-toolbar-root .rm-empty { color:#596579; line-height:1.6; }
        @media (pointer:coarse) { #rm-toolbar-root .rm-dock button, #rm-toolbar-root .rm-chip, #rm-toolbar-root .rm-menu-btn, #rm-toolbar-root .rm-menu-option, #rm-toolbar-root .rm-panel-close { min-height:44px; min-width:44px; } }
        @media (prefers-reduced-motion:reduce) { #rm-pins-container .rm-pin, #rm-toolbar-root .rm-toast { animation:none; transition:none; } }
      `;
      document.head.appendChild(style);
    },
  });

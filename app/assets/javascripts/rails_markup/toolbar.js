/**
 * Rails Markup Toolbar — self-contained annotation UI
 * No dependencies (no Stimulus, no importmap). Works in any Rails app.
 *
 * Usage: include via <script> tag, then call:
 *   RailsMarkupToolbar.init({ endpoint: "/feedback/api", accent: "indigo" })
 */
(function(global) {
  "use strict";

  const RailsMarkupToolbar = {
    // State
    annotations: [],
    nextId: 1,
    active: false,
    serverOnline: false,
    sessionId: null,
    sseSource: null,
    healthInterval: null,
    hoveredElement: null,
    selectedText: null,
    clickedElement: null,
    activeFilter: "all",
    editingId: null,

    // Config
    endpoint: "/feedback/api",
    accent: "indigo",

    // DOM refs (set in init)
    root: null,

    init(opts = {}) {
      this.endpoint = opts.endpoint || "/feedback/api";
      this.accent = opts.accent || "indigo";
      this._currentPathname = window.location.pathname;

      if (document.getElementById("rm-toolbar-root")) return;
      this._injectStyles();
      this._injectDOM();
      this._bindEvents();
      this._loadFromStorage();
      this._checkHealth();
      this.healthInterval = setInterval(() => this._checkHealth(), 10000);
      this._boundVisibilityChange = () => this._onVisibilityChange();
      document.addEventListener("visibilitychange", this._boundVisibilityChange);
      this._renderPins();
      this._updateCount();
    },

    destroy() {
      this._deactivateMode();
      if (this.sseSource) { this.sseSource.close(); this.sseSource = null; }
      if (this.healthInterval) { clearInterval(this.healthInterval); this.healthInterval = null; }
      if (this._boundVisibilityChange) document.removeEventListener("visibilitychange", this._boundVisibilityChange);
      window.removeEventListener("resize", this._onResize);
      if (this._boundTurboNavigate) document.removeEventListener("turbo:load", this._boundTurboNavigate);
      if (this._boundTurboFrame) document.removeEventListener("turbo:frame-render", this._boundTurboFrame);
      const root = document.getElementById("rm-toolbar-root");
      if (root) root.remove();
      const styles = document.getElementById("rm-toolbar-styles");
      if (styles) styles.remove();
    },

    // ---- DOM injection ----

    _injectStyles() {
      if (document.getElementById("rm-toolbar-styles")) return;
      const style = document.createElement("style");
      style.id = "rm-toolbar-styles";
      style.textContent = `
        @keyframes rm-pulse { 0%,100%{box-shadow:0 2px 8px rgba(0,0,0,0.2)} 50%{box-shadow:0 2px 12px rgba(0,0,0,0.3),0 0 0 4px rgba(99,102,241,0.15)} }
        @keyframes rm-toast-in { from{opacity:0;transform:translateY(16px) scale(0.95)} to{opacity:1;transform:translateY(0) scale(1)} }
        @keyframes rm-toast-out { from{opacity:1;transform:translateY(0) scale(1)} to{opacity:0;transform:translateY(16px) scale(0.95)} }
        #rm-toolbar-root * { box-sizing:border-box; font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,"Helvetica Neue",sans-serif; }
        .rm-fab { position:fixed; bottom:24px; left:24px; z-index:9980; width:48px; height:48px; border-radius:50%; border:none; cursor:pointer; display:flex; align-items:center; justify-content:center; transition:all 0.2s; box-shadow:0 4px 12px rgba(0,0,0,0.15); }
        .rm-fab svg { width:20px; height:20px; fill:none; stroke:currentColor; stroke-width:2; stroke-linecap:round; stroke-linejoin:round; }
        .rm-fab-badge { position:absolute; top:-4px; right:-4px; min-width:20px; height:20px; padding:0 4px; border-radius:10px; background:#ef4444; color:#fff; font-size:11px; font-weight:700; display:none; align-items:center; justify-content:center; }
        .rm-panel-toggle { position:fixed; bottom:24px; left:80px; z-index:9980; width:32px; height:32px; border-radius:50%; border:1px solid #e5e7eb; background:rgba(255,255,255,0.9); cursor:pointer; display:none; align-items:center; justify-content:center; color:#6b7280; transition:all 0.2s; backdrop-filter:blur(8px); }
        .rm-panel-toggle:hover { color:#4361ee; }
        .rm-panel-toggle svg { width:16px; height:16px; fill:none; stroke:currentColor; stroke-width:2; stroke-linecap:round; stroke-linejoin:round; }
        .rm-toast-container { position:fixed; bottom:80px; left:24px; z-index:9983; display:flex; flex-direction:column; gap:8px; pointer-events:none; }
        .rm-pins-container { position:absolute; top:0; left:0; width:100%; z-index:9979; pointer-events:auto; }
        .rm-popup { display:none; position:fixed; z-index:9982; width:360px; background:rgba(255,255,255,0.95); backdrop-filter:blur(12px); border-radius:16px; box-shadow:0 25px 50px rgba(0,0,0,0.1); border:1px solid rgba(229,231,235,0.8); padding:16px; }
        .rm-popup textarea { width:100%; font-size:13px; border:1px solid #e5e7eb; border-radius:12px; padding:12px; resize:none; outline:none; font-family:inherit; transition:border-color 0.15s,box-shadow 0.15s; }
        .rm-popup textarea:focus { border-color:#818cf8; box-shadow:0 0 0 3px rgba(99,102,241,0.1); }
        .rm-popup select { font-size:11px; font-weight:500; border:1px solid #e5e7eb; border-radius:8px; padding:6px 24px 6px 8px; background:#fff; appearance:none; cursor:pointer; }
        .rm-popup select:focus { outline:none; border-color:#818cf8; box-shadow:0 0 0 3px rgba(99,102,241,0.1); }
        .rm-popup-el { font-size:11px; color:#9ca3af; font-family:monospace; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; line-height:1.4; }
        .rm-popup-text { font-size:12px; color:#6b7280; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; margin-top:2px; line-height:1.4; }
        .rm-popup-actions { display:flex; align-items:center; gap:8px; margin-top:8px; }
        .rm-popup-actions .rm-count { font-size:10px; color:#d1d5db; margin-left:auto; font-variant-numeric:tabular-nums; }
        .rm-btn-cancel { padding:6px 12px; font-size:12px; color:#9ca3af; background:none; border:none; cursor:pointer; border-radius:8px; }
        .rm-btn-cancel:hover { color:#6b7280; }
        .rm-btn-submit { padding:6px 16px; font-size:12px; font-weight:500; color:#fff; border:none; border-radius:8px; cursor:pointer; display:inline-flex; align-items:center; gap:6px; }
        .rm-btn-submit kbd { font-size:9px; opacity:0.6; font-family:sans-serif; }
        .rm-panel { display:none; position:fixed; bottom:80px; left:24px; z-index:9981; width:380px; max-height:60vh; background:rgba(255,255,255,0.95); backdrop-filter:blur(12px); border-radius:16px; box-shadow:0 25px 50px rgba(0,0,0,0.1); border:1px solid rgba(229,231,235,0.8); flex-direction:column; }
        .rm-panel-header { display:flex; align-items:center; justify-content:space-between; padding:12px 16px; border-bottom:1px solid #f3f4f6; }
        .rm-panel-header h3 { font-size:14px; font-weight:600; color:#1f2937; }
        .rm-panel-count { min-width:20px; text-align:center; padding:2px 6px; font-size:10px; font-weight:600; border-radius:10px; }
        .rm-panel-close { padding:6px; color:#d1d5db; background:none; border:none; cursor:pointer; border-radius:8px; }
        .rm-panel-close:hover { color:#6b7280; }
        .rm-panel-close svg { width:16px; height:16px; fill:none; stroke:currentColor; stroke-width:2; stroke-linecap:round; stroke-linejoin:round; }
        .rm-filter-chips { display:flex; gap:6px; padding:8px 16px; border-bottom:1px solid #f9fafb; }
        .rm-chip { padding:4px 8px; font-size:10px; font-weight:500; border-radius:10px; cursor:pointer; transition:all 0.15s; border:none; }
        .rm-chip-active { color:#fff; }
        .rm-chip-inactive { background:#f9fafb; color:#9ca3af; }
        .rm-chip-inactive:hover { color:#6b7280; }
        .rm-panel-list { flex:1; overflow-y:auto; padding:12px; display:flex; flex-direction:column; gap:8px; }
        .rm-panel-footer { display:flex; align-items:center; gap:8px; padding:10px 16px; border-top:1px solid #f3f4f6; font-size:11px; color:#9ca3af; }
        .rm-status-dot { width:8px; height:8px; border-radius:50%; background:#d1d5db; }
        .rm-card { padding:12px; background:#fff; border-radius:8px; border:1px solid #f3f4f6; border-left:3px solid; cursor:pointer; transition:all 0.15s; }
        .rm-card:hover { box-shadow:0 2px 8px rgba(0,0,0,0.05); }
        .rm-card-top { display:flex; align-items:center; gap:6px; flex-wrap:wrap; }
        .rm-card-dot { width:8px; height:8px; border-radius:50%; flex-shrink:0; }
        .rm-card-id { font-size:10px; font-weight:600; color:#9ca3af; }
        .rm-card-badge { padding:2px 6px; font-size:10px; font-weight:500; border-radius:10px; }
        .rm-card-body { margin-top:6px; font-size:13px; line-height:1.5; color:#1f2937; }
        .rm-card-path { margin-top:4px; font-size:10px; color:#d1d5db; font-family:monospace; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }
        .rm-card-thread { margin-top:8px; padding:8px; background:rgba(249,250,251,0.8); border-radius:8px; font-size:12px; color:#6b7280; border-left:2px solid; }
        .rm-card-thread-role { font-size:10px; font-weight:500; color:#9ca3af; text-transform:uppercase; letter-spacing:0.05em; }
        .rm-empty { text-align:center; padding:32px 16px; color:#9ca3af; }
        .rm-empty-icon { font-size:32px; margin-bottom:8px; }
        .rm-empty-text { font-size:13px; }
        .rm-pin { position:absolute; display:flex; align-items:center; justify-content:center; width:20px; height:20px; border-radius:50%; color:#fff; font-size:10px; font-weight:700; cursor:pointer; transition:transform 0.2s; z-index:9979; box-shadow:0 2px 8px rgba(0,0,0,0.2); }
        .rm-pin:hover { transform:scale(1.25); }
        .rm-pin-active { animation:rm-pulse 2s ease-in-out infinite; }
        .rm-toast { padding:8px 12px; border-radius:8px; border:1px solid; font-size:12px; font-weight:500; box-shadow:0 2px 8px rgba(0,0,0,0.05); animation:rm-toast-in 0.3s ease; }
      `;
      document.head.appendChild(style);
    },

    _injectDOM() {
      const root = document.createElement("div");
      root.id = "rm-toolbar-root";

      const accentBg = this._accentBg();
      const accentBgHover = this._accentBgHover();
      const accentLight = this._accentLight();
      const accentText = this._accentText();

      root.innerHTML = `
        <button class="rm-fab" id="rm-fab" style="background:${accentBg};color:#fff;" title="Toggle annotation mode" aria-label="Toggle annotation mode" aria-expanded="false" aria-controls="rm-panel">
          <svg viewBox="0 0 24 24"><path d="M21 15a2 2 0 01-2 2H7l-4 4V5a2 2 0 012-2h14a2 2 0 012 2z"/></svg>
          <span class="rm-fab-badge" id="rm-fab-badge"></span>
        </button>
        <button class="rm-panel-toggle" id="rm-panel-toggle" title="View annotations" aria-label="View annotations" aria-controls="rm-panel">
          <svg viewBox="0 0 24 24"><path d="M4 6h16M4 12h16M4 18h7"/></svg>
        </button>
        <div class="rm-toast-container" id="rm-toast-container"></div>
        <div class="rm-pins-container" id="rm-pins-container"></div>
        <div class="rm-popup" id="rm-popup" role="dialog" aria-label="Add annotation" aria-modal="false">
          <div style="margin-bottom:12px">
            <p class="rm-popup-el" id="rm-popup-el"></p>
            <p class="rm-popup-text" id="rm-popup-text"></p>
          </div>
          <textarea id="rm-popup-input" rows="3" placeholder="What should change?"></textarea>
          <div style="display:flex;align-items:center;gap:8px;margin-top:12px">
            <select id="rm-intent-select">
              <option value="fix">Fix</option>
              <option value="change" selected>Change</option>
              <option value="question">Question</option>
              <option value="approve">Approve</option>
            </select>
            <select id="rm-severity-select">
              <option value="suggestion" selected>Suggestion</option>
              <option value="important">Important</option>
              <option value="blocking">Blocking</option>
            </select>
            <span class="rm-count" id="rm-char-count"></span>
          </div>
          <div class="rm-popup-actions">
            <button class="rm-btn-cancel" id="rm-btn-cancel">Cancel</button>
            <button class="rm-btn-submit" id="rm-btn-submit" style="background:${accentBg}">
              <span id="rm-submit-label">Add</span>
              <kbd>⌘↩</kbd>
            </button>
          </div>
        </div>
        <div class="rm-panel" id="rm-panel" role="dialog" aria-label="Annotations panel">
          <div class="rm-panel-header">
            <div style="display:flex;align-items:center;gap:8px">
              <h3>Feedback</h3>
              <span class="rm-panel-count" id="rm-panel-count" style="background:${accentLight};color:${accentText}">0</span>
            </div>
            <button class="rm-panel-close" id="rm-panel-close" aria-label="Close annotations panel">
              <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M6 18L18 6M6 6l12 12"/></svg>
            </button>
          </div>
          <div class="rm-filter-chips" id="rm-filter-chips">
            <button class="rm-chip rm-chip-active" data-filter="all" style="background:${accentBg}">All</button>
            <button class="rm-chip rm-chip-inactive" data-filter="pending">Pending</button>
            <button class="rm-chip rm-chip-inactive" data-filter="resolved">Resolved</button>
          </div>
          <div class="rm-panel-list" id="rm-panel-list"></div>
          <div class="rm-panel-footer">
            <span class="rm-status-dot" id="rm-status-dot"></span>
            <span id="rm-status-text">Offline</span>
          </div>
        </div>
      `;

      document.body.appendChild(root);
      this.root = root;
      this._onResize = this._debouncedRepositionPins();
      window.addEventListener("resize", this._onResize);
    },

    _bindEvents() {
      const self = this;
      document.getElementById("rm-fab").addEventListener("click", () => self.toggleMode());
      document.getElementById("rm-panel-toggle").addEventListener("click", () => self.togglePanel());
      document.getElementById("rm-panel-close").addEventListener("click", () => self.togglePanel());
      document.getElementById("rm-btn-cancel").addEventListener("click", () => self._closePopup());
      document.getElementById("rm-btn-submit").addEventListener("click", (e) => self.submitAnnotation(e));
      document.getElementById("rm-popup-input").addEventListener("input", () => self._updateCharCount());
      document.getElementById("rm-filter-chips").addEventListener("click", (e) => {
        const chip = e.target.closest("[data-filter]");
        if (chip) self._filterAnnotations(chip.dataset.filter);
      });

      // Event delegation for cards (click scrolls to element)
      document.getElementById("rm-panel-list").addEventListener("click", (e) => {
        const card = e.target.closest("[data-card-id]");
        if (!card) return;
        const id = parseInt(card.dataset.cardId, 10);
        const annotation = self.annotations.find(a => a.id === id);
        if (!annotation) return;
        const el = self._findElement(annotation);
        if (el) el.scrollIntoView({ behavior: "smooth", block: "center" });
      });

      // Event delegation for pins (click opens panel + scrolls to card)
      document.getElementById("rm-pins-container").addEventListener("click", (e) => {
        const pin = e.target.closest("[data-pin-id]");
        if (!pin) return;
        const panel = document.getElementById("rm-panel");
        if (panel.style.display !== "flex") self.togglePanel();
        const card = document.querySelector('[data-card-id="' + pin.dataset.pinId + '"]');
        if (card) card.scrollIntoView({ behavior: "smooth", block: "center" });
      });

      this._boundMouseMove = (e) => self._handleMouseMove(e);
      this._boundMouseDown = (e) => self._handleMouseDown(e);
      this._boundMouseUp = (e) => self._handleMouseUp(e);
      this._boundClick = (e) => self._handleClick(e);
      this._boundKeyDown = (e) => self._handleKeyDown(e);

      // Turbo Drive — full page navigation, reload annotations for new URL
      this._boundTurboNavigate = () => self._onTurboNavigate();
      document.addEventListener("turbo:load", this._boundTurboNavigate);
      // Turbo Frames — partial DOM update, reposition pins
      this._boundTurboFrame = () => self._onTurboFrameRender();
      document.addEventListener("turbo:frame-render", this._boundTurboFrame);
    },

    // ---- Turbo integration ----

    _currentPathname: null,

    _onTurboNavigate() {
      const newPath = window.location.pathname;
      if (newPath === this._currentPathname) return; // same page (anchor change, etc.)
      this._currentPathname = newPath;

      // Deactivate crosshair mode
      this._deactivateMode();

      // Close popup
      const popup = document.getElementById("rm-popup");
      if (popup && popup.style.display === "block") this._closePopup();

      // Close panel
      const panel = document.getElementById("rm-panel");
      if (panel) panel.style.display = "none";

      // Clear pins
      const pinsContainer = document.getElementById("rm-pins-container");
      if (pinsContainer) pinsContainer.innerHTML = "";

      // Reset state and reload from storage for new URL
      this.annotations = [];
      this.nextId = 1;
      this._loadFromStorage();
      this._renderPins();
      this._updateCount();
      this._rebuildList();

      // Re-init session for new URL
      if (this.serverOnline) this._initSession();
    },

    _onTurboFrameRender() {
      // Frame content changed — DOM elements may have moved, reposition pins
      this._repositionPins();
    },

    // ---- Mode ----

    toggleMode() {
      this.active = !this.active;
      if (this.active) {
        this._activateMode();
        // Always open panel when activating annotation mode
        if (document.getElementById("rm-panel").style.display !== "flex") {
          this.togglePanel();
        }
      } else {
        this._deactivateMode();
      }
    },

    _activateMode() {
      document.body.style.cursor = "crosshair";
      const fab = document.getElementById("rm-fab");
      fab.style.transform = "scale(0.9)";
      fab.style.boxShadow = `0 0 0 3px ${this._accentBg()}, 0 0 0 6px rgba(99,102,241,0.2)`;
      fab.innerHTML = '<svg viewBox="0 0 24 24" style="width:20px;height:20px;fill:none;stroke:currentColor;stroke-width:2;stroke-linecap:round;stroke-linejoin:round"><path d="M6 18L18 6M6 6l12 12"/></svg><span class="rm-fab-badge" id="rm-fab-badge">' + (document.getElementById("rm-fab-badge")?.textContent || "") + '</span>';
      document.addEventListener("mousemove", this._boundMouseMove, true);
      document.addEventListener("mousedown", this._boundMouseDown, true);
      document.addEventListener("mouseup", this._boundMouseUp, true);
      document.addEventListener("click", this._boundClick, true);
      document.addEventListener("keydown", this._boundKeyDown, true);
    },

    _deactivateMode() {
      this.active = false;
      document.body.style.cursor = "";
      const fab = document.getElementById("rm-fab");
      if (fab) {
        fab.style.transform = "";
        fab.style.boxShadow = "0 4px 12px rgba(0,0,0,0.15)";
        fab.innerHTML = '<svg viewBox="0 0 24 24" style="width:20px;height:20px;fill:none;stroke:currentColor;stroke-width:2;stroke-linecap:round;stroke-linejoin:round"><path d="M21 15a2 2 0 01-2 2H7l-4 4V5a2 2 0 012-2h14a2 2 0 012 2z"/></svg><span class="rm-fab-badge" id="rm-fab-badge">' + (this.annotations.length || "") + '</span>';
        this._updateCount();
      }
      document.removeEventListener("mousemove", this._boundMouseMove, true);
      document.removeEventListener("mousedown", this._boundMouseDown, true);
      document.removeEventListener("mouseup", this._boundMouseUp, true);
      document.removeEventListener("click", this._boundClick, true);
      document.removeEventListener("keydown", this._boundKeyDown, true);
      this._removeHighlight();
    },

    // ---- Panel ----

    togglePanel() {
      const panel = document.getElementById("rm-panel");
      const fab = document.getElementById("rm-fab");
      if (panel.style.display === "flex") {
        panel.style.display = "none";
        if (fab) fab.setAttribute("aria-expanded", "false");
      } else {
        panel.style.display = "flex";
        if (fab) fab.setAttribute("aria-expanded", "true");
      }
    },

    // ---- Mouse handlers ----

    _handleMouseMove(event) {
      if (!this.active) return;
      const el = document.elementFromPoint(event.clientX, event.clientY);
      if (!el || this._isToolbar(el)) { this._removeHighlight(); return; }
      if (el === this.hoveredElement) return;
      this._removeHighlight();
      this.hoveredElement = el;
      el.dataset.rmOrigOutline = el.style.outline || "";
      el.style.outline = `2px solid ${this._accentBg()}`;
      el.style.outlineOffset = "2px";
    },

    _handleMouseDown(event) {
      const el = document.elementFromPoint(event.clientX, event.clientY);
      if (el && !this._isToolbar(el)) this.clickedElement = el;
    },

    _handleMouseUp(event) {
      if (!this.active) return;
      const el = this.clickedElement || document.elementFromPoint(event.clientX, event.clientY);
      if (!el || this._isToolbar(el)) return;
      event.preventDefault();
      event.stopPropagation();
      const sel = window.getSelection();
      this.selectedText = (sel && sel.toString().trim().length > 0) ? sel.toString().trim() : null;
      this._currentElement = this._identify(el);
      this._showPopup(event.clientX, event.clientY);
      this.clickedElement = null;
    },

    _handleClick(event) {
      if (!this.active) return;
      const el = event.target;
      if (this._isToolbar(el)) return;
      // Block link navigation and Turbo visits while annotating
      event.preventDefault();
      event.stopPropagation();
    },

    _handleKeyDown(event) {
      if (event.key === "Escape") {
        const popup = document.getElementById("rm-popup");
        if (popup && popup.style.display === "block") {
          this._closePopup();
        } else {
          this._deactivateMode();
        }
      }
      if ((event.metaKey || event.ctrlKey) && event.key === "Enter") {
        const popup = document.getElementById("rm-popup");
        if (popup && popup.style.display === "block") {
          this.submitAnnotation();
        }
      }
    },

    // ---- Element identification ----

    _identify(el) {
      const tag = el.tagName.toLowerCase();
      const id = el.id ? "#" + el.id : "";
      const cls = Array.from(el.classList).filter(c => !c.startsWith("rm-")).slice(0, 5).map(c => "." + c).join("");
      const text = (el.textContent || "").trim().slice(0, 80);
      const rect = el.getBoundingClientRect();
      return {
        selector: tag + id + cls,
        cssPath: this._cssPath(el),
        nearbyText: text,
        boundingBox: { top: Math.round(rect.top + window.scrollY), left: Math.round(rect.left + window.scrollX), width: Math.round(rect.width), height: Math.round(rect.height) }
      };
    },

    _cssPath(el) {
      const parts = [];
      let cur = el;
      while (cur && cur !== document.body && parts.length < 5) {
        let sel = cur.tagName.toLowerCase();
        if (cur.id) { sel += "#" + cur.id; parts.unshift(sel); break; }
        const parent = cur.parentElement;
        if (parent) {
          const sibs = Array.from(parent.children).filter(c => c.tagName === cur.tagName);
          if (sibs.length > 1) sel += ":nth-of-type(" + (sibs.indexOf(cur) + 1) + ")";
        }
        parts.unshift(sel);
        cur = cur.parentElement;
      }
      return parts.join(" > ");
    },

    // ---- Popup ----

    _showPopup(x, y) {
      const popup = document.getElementById("rm-popup");
      popup.style.display = "block";
      popup.style.opacity = "0";
      popup.style.left = "-9999px";
      popup.style.top = "-9999px";
      const pw = popup.offsetWidth || 360;
      const ph = popup.offsetHeight || 300;
      let left = Math.min(x + 10, window.innerWidth - pw - 20);
      let top = Math.min(y + 10, window.innerHeight - ph - 20);
      left = Math.max(10, left);
      top = Math.max(10, top);
      popup.style.left = left + "px";
      popup.style.top = top + "px";
      requestAnimationFrame(() => {
        popup.style.transition = "opacity 0.2s ease";
        popup.style.opacity = "1";
      });
      document.getElementById("rm-popup-el").textContent = this._currentElement.selector;
      document.getElementById("rm-popup-text").textContent = this.selectedText
        ? '"' + this.selectedText.slice(0, 60) + '"'
        : this._currentElement.nearbyText.slice(0, 60);
      const input = document.getElementById("rm-popup-input");
      input.value = "";
      document.getElementById("rm-intent-select").value = "change";
      document.getElementById("rm-severity-select").value = "suggestion";
      document.getElementById("rm-char-count").textContent = "";
      document.getElementById("rm-submit-label").textContent = "Add";
      setTimeout(() => input.focus(), 50);
    },

    _closePopup() {
      const popup = document.getElementById("rm-popup");
      popup.style.transition = "opacity 0.15s ease";
      popup.style.opacity = "0";
      setTimeout(() => { popup.style.display = "none"; popup.style.transition = ""; popup.style.opacity = ""; }, 150);
      document.getElementById("rm-popup-input").value = "";
      this.selectedText = null;
      this._currentElement = null;
      this.editingId = null;
      document.getElementById("rm-submit-label").textContent = "Add";
    },

    _updateCharCount() {
      const len = document.getElementById("rm-popup-input").value.length;
      const el = document.getElementById("rm-char-count");
      el.textContent = len > 0 ? len : "";
      el.style.color = len > 500 ? "#f87171" : "#d1d5db";
    },

    // ---- Submit ----

    submitAnnotation(event) {
      if (event) event.preventDefault();
      const comment = document.getElementById("rm-popup-input").value.trim();
      if (!comment) return;
      const intent = document.getElementById("rm-intent-select").value;
      const severity = document.getElementById("rm-severity-select").value;

      const annotation = {
        id: this.nextId++,
        comment, intent, severity,
        element: this._currentElement,
        selectedText: this.selectedText || null,
        url: window.location.href,
        pathname: window.location.pathname,
        timestamp: new Date().toISOString(),
        status: "pending",
        thread: []
      };

      this.annotations.push(annotation);
      this._saveToStorage();
      this._renderPin(annotation);
      this._renderCard(annotation);
      this._updateCount();
      this._closePopup();
      this._pushToServer(annotation);
    },

    // ---- Filters ----

    _filterAnnotations(filter) {
      this.activeFilter = filter;
      this._updateFilterChips();
      this._rebuildList();
    },

    _updateFilterChips() {
      const chips = document.querySelectorAll("#rm-filter-chips [data-filter]");
      chips.forEach(chip => {
        if (chip.dataset.filter === this.activeFilter) {
          chip.className = "rm-chip rm-chip-active";
          chip.style.background = this._accentBg();
          chip.style.color = "#fff";
        } else {
          chip.className = "rm-chip rm-chip-inactive";
          chip.style.background = "#f9fafb";
          chip.style.color = "#9ca3af";
        }
      });
    },

    _filteredAnnotations() {
      if (this.activeFilter === "all") return this.annotations;
      if (this.activeFilter === "pending") return this.annotations.filter(a => a.status === "pending" || a.status === "acknowledged");
      if (this.activeFilter === "resolved") return this.annotations.filter(a => a.status === "resolved" || a.status === "dismissed");
      return this.annotations;
    },

    // ---- Panel cards ----

    _renderCard(annotation) {
      const list = document.getElementById("rm-panel-list");
      const card = document.createElement("div");
      card.className = "rm-card";
      card.dataset.cardId = annotation.id;

      const borderColor = annotation.status === "resolved" ? "#10b981" : annotation.status === "dismissed" ? "#d1d5db" : this._accentBg();
      card.style.borderLeftColor = borderColor;

      const dotColor = { pending: "#3b82f6", acknowledged: "#f59e0b", resolved: "#10b981", dismissed: "#d1d5db" }[annotation.status] || "#3b82f6";
      const intentColors = { fix: { bg: "#fef2f2", text: "#dc2626" }, change: { bg: "#eff6ff", text: "#2563eb" }, question: { bg: "#f5f3ff", text: "#7c3aed" }, approve: { bg: "#ecfdf5", text: "#059669" } };
      const ic = intentColors[annotation.intent] || intentColors.change;

      let threadHtml = "";
      const thread = annotation.thread || [];
      if (thread.length > 0) {
        const last = thread[thread.length - 1];
        threadHtml = `<div class="rm-card-thread" style="border-left-color:${this._accentBg()}"><span class="rm-card-thread-role">${this._esc(last.role || "agent")}</span><div style="margin-top:2px">${this._esc(last.message)}</div></div>`;
      }

      card.innerHTML = `
        <div class="rm-card-top">
          <span class="rm-card-dot" style="background:${dotColor}"></span>
          <span class="rm-card-id">#${annotation.id}</span>
          <span class="rm-card-badge" style="background:${ic.bg};color:${ic.text}">${annotation.intent}</span>
          ${annotation.severity !== "suggestion" ? '<span class="rm-card-badge" style="background:#fff7ed;color:#9a3412">' + annotation.severity + '</span>' : ''}
        </div>
        <div class="rm-card-body">${this._esc(annotation.comment)}</div>
        <div class="rm-card-path">${this._esc(annotation.element?.selector || "")}</div>
        ${annotation.selectedText ? '<div class="rm-card-path" style="font-style:italic">"' + this._esc(annotation.selectedText.slice(0, 60)) + '"</div>' : ''}
        ${threadHtml}
      `;

      list.appendChild(card);
    },

    _rebuildList() {
      const list = document.getElementById("rm-panel-list");
      list.innerHTML = "";
      const filtered = this._filteredAnnotations();
      if (filtered.length === 0) {
        list.innerHTML = '<div class="rm-empty"><div class="rm-empty-icon">&#9670;</div><div class="rm-empty-text">No annotations yet</div></div>';
        return;
      }
      filtered.forEach(a => this._renderCard(a));
    },

    _updateCount() {
      const count = this.annotations.length;
      const countEl = document.getElementById("rm-panel-count");
      if (countEl) countEl.textContent = count;
      const badge = document.getElementById("rm-fab-badge");
      if (badge) {
        if (count > 0) { badge.textContent = count; badge.style.display = "flex"; }
        else { badge.style.display = "none"; }
      }
      const toggle = document.getElementById("rm-panel-toggle");
      if (toggle) toggle.style.display = "flex";
    },

    // ---- Pins ----

    _renderPin(annotation) {
      if (!annotation.element?.boundingBox) return;
      const { top, left, width } = annotation.element.boundingBox;
      const isResolved = annotation.status === "resolved" || annotation.status === "dismissed";
      const pin = document.createElement("div");
      pin.className = "rm-pin" + (isResolved ? "" : " rm-pin-active");
      pin.dataset.pinId = annotation.id;
      pin.style.top = (top - 10) + "px";
      pin.style.left = (left + width - 10) + "px";
      pin.style.background = isResolved ? "#d1d5db" : this._accentBg();
      if (isResolved) pin.style.opacity = "0.6";
      pin.textContent = annotation.id;
      pin.title = "#" + annotation.id + ": " + annotation.comment.slice(0, 50);
      document.getElementById("rm-pins-container").appendChild(pin);
    },

    _renderPins() {
      const container = document.getElementById("rm-pins-container");
      if (container) container.innerHTML = "";
      this.annotations.forEach(a => this._renderPin(a));
    },

    _findElement(annotation) {
      if (!annotation.element) return null;
      const { cssPath, selector } = annotation.element;
      if (cssPath) { try { const el = document.querySelector(cssPath); if (el) return el; } catch {} }
      if (selector) { try { const el = document.querySelector(selector); if (el) return el; } catch {} }
      return null;
    },

    _repositionPins() {
      this.annotations.forEach(annotation => {
        const el = this._findElement(annotation);
        if (!el) return;
        const rect = el.getBoundingClientRect();
        annotation.element.boundingBox = { top: Math.round(rect.top + window.scrollY), left: Math.round(rect.left + window.scrollX), width: Math.round(rect.width), height: Math.round(rect.height) };
        const pin = document.querySelector('[data-pin-id="' + annotation.id + '"]');
        if (pin) { pin.style.top = (annotation.element.boundingBox.top - 10) + "px"; pin.style.left = (annotation.element.boundingBox.left + annotation.element.boundingBox.width - 10) + "px"; }
      });
    },

    _debouncedRepositionPins() {
      let timer = null;
      return () => { if (timer) clearTimeout(timer); timer = setTimeout(() => this._repositionPins(), 250); };
    },

    // ---- Highlight ----

    _removeHighlight() {
      if (this.hoveredElement) {
        this.hoveredElement.style.outline = this.hoveredElement.dataset.rmOrigOutline || "";
        this.hoveredElement.style.outlineOffset = "";
        delete this.hoveredElement.dataset.rmOrigOutline;
        this.hoveredElement = null;
      }
    },

    _isToolbar(el) {
      const root = document.getElementById("rm-toolbar-root");
      return root && root.contains(el);
    },

    // ---- Toast ----

    _showToast(message, type) {
      const container = document.getElementById("rm-toast-container");
      if (!container) return;
      const toast = document.createElement("div");
      toast.className = "rm-toast";
      const colors = { resolved: { bg: "#ecfdf5", border: "#a7f3d0", text: "#065f46" }, dismissed: { bg: "#f3f4f6", border: "#e5e7eb", text: "#6b7280" } };
      const c = colors[type] || { bg: this._accentLight(), border: this._accentBg(), text: this._accentText() };
      toast.style.background = c.bg;
      toast.style.borderColor = c.border;
      toast.style.color = c.text;
      toast.textContent = message;
      container.appendChild(toast);
      setTimeout(() => { toast.style.animation = "rm-toast-out 0.3s ease forwards"; setTimeout(() => toast.remove(), 300); }, 4000);
    },

    // ---- Storage ----

    _storageKey() { return "rm-annotations:" + window.location.pathname; },

    _saveToStorage() {
      try { localStorage.setItem(this._storageKey(), JSON.stringify({ annotations: this.annotations, nextId: this.nextId })); }
      catch (e) { console.warn("[rails-markup] save failed:", e); }
    },

    _loadFromStorage() {
      try {
        const raw = localStorage.getItem(this._storageKey());
        if (!raw) return;
        const data = JSON.parse(raw);
        if (data.annotations) {
          this.annotations = data.annotations;
          this.nextId = data.nextId || (this.annotations.length + 1);
          this._rebuildList();
          this._updateCount();
        }
      } catch (e) { console.warn("[rails-markup] load failed:", e); }
    },

    // ---- Server sync ----

    _onVisibilityChange() {
      if (document.hidden) {
        // Tab hidden — pause health checks to save resources
        if (this.healthInterval) { clearInterval(this.healthInterval); this.healthInterval = null; }
      } else {
        // Tab visible — resume health checks immediately
        if (!this.healthInterval) {
          this._checkHealth();
          this.healthInterval = setInterval(() => this._checkHealth(), 10000);
        }
      }
    },

    async _checkHealth() {
      try {
        const resp = await fetch(this.endpoint + "/health", { signal: AbortSignal.timeout(3000) });
        const was = this.serverOnline;
        this.serverOnline = resp.ok;
        this._updateStatus();
        if (!was && this.serverOnline) await this._initSession();
      } catch {
        this.serverOnline = false;
        this._updateStatus();
      }
    },

    async _initSession() {
      if (!this.serverOnline) return;
      try {
        const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content;
        const headers = { "Content-Type": "application/json" };
        if (csrfToken) headers["X-CSRF-Token"] = csrfToken;
        const resp = await fetch(this.endpoint + "/sessions", {
          method: "POST", headers, credentials: "same-origin",
          body: JSON.stringify({ url: window.location.href, metadata: { tool: "rails-markup" } }),
          signal: AbortSignal.timeout(5000)
        });
        if (resp.ok) {
          const data = await resp.json();
          this.sessionId = data.id;
        }
      } catch (e) { console.warn("[rails-markup] session init failed:", e); }
    },

    async _pushToServer(annotation) {
      if (!this.serverOnline) return;
      try {
        const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content;
        const headers = { "Content-Type": "application/json" };
        if (csrfToken) headers["X-CSRF-Token"] = csrfToken;
        await fetch(this.endpoint + "/sessions/" + (this.sessionId || "local") + "/annotations", {
          method: "POST", headers, credentials: "same-origin",
          body: JSON.stringify({
            page_url: annotation.pathname,
            content: annotation.comment,
            intent: annotation.intent,
            severity: annotation.severity,
            selected_text: annotation.selectedText || null,
            target: annotation.element || {},
            metadata: { localId: annotation.id, url: annotation.url }
          }),
          signal: AbortSignal.timeout(5000)
        });
      } catch (e) { console.warn("[rails-markup] push failed:", e); }
    },

    _updateStatus() {
      const dot = document.getElementById("rm-status-dot");
      const text = document.getElementById("rm-status-text");
      if (dot) {
        dot.style.background = this.serverOnline ? "#4ade80" : "#d1d5db";
        dot.style.boxShadow = this.serverOnline ? "0 0 0 2px rgba(74,222,128,0.2)" : "";
      }
      if (text) text.textContent = this.serverOnline ? "Connected" : "Offline";
    },

    // ---- Color helpers ----

    _accentBg() {
      const map = { indigo: "#4f46e5", amber: "#f59e0b", blue: "#2563eb", emerald: "#059669", rose: "#e11d48" };
      return map[this.accent] || map.indigo;
    },
    _accentBgHover() {
      const map = { indigo: "#4338ca", amber: "#d97706", blue: "#1d4ed8", emerald: "#047857", rose: "#be123c" };
      return map[this.accent] || map.indigo;
    },
    _accentLight() {
      const map = { indigo: "#e0e7ff", amber: "#fef3c7", blue: "#dbeafe", emerald: "#d1fae5", rose: "#ffe4e6" };
      return map[this.accent] || map.indigo;
    },
    _accentText() {
      const map = { indigo: "#3730a3", amber: "#92400e", blue: "#1e40af", emerald: "#065f46", rose: "#9f1239" };
      return map[this.accent] || map.indigo;
    },

    // ---- Helpers ----

    _esc(str) {
      const div = document.createElement("div");
      div.textContent = str || "";
      return div.innerHTML;
    }
  };

  global.RailsMarkupToolbar = RailsMarkupToolbar;
})(typeof window !== "undefined" ? window : this);

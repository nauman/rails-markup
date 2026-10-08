  Object.assign(RailsMarkupToolbar, {
    _injectDOM() {
      const root = document.createElement("div");
      root.id = "rm-toolbar-root";

      const accentBg = this._accentBg();
      const accentBgHover = this._accentBgHover();
      const accentLight = this._accentLight();
      const accentText = this._accentText();

      // Position: bl (bottom-left), br (bottom-right), tl (top-left), tr (top-right)
      const posMap = { bl: "bottom:24px;left:24px;", br: "bottom:24px;right:24px;", tl: "top:24px;left:24px;", tr: "top:24px;right:24px;" };
      const fabPos = posMap[this.position] || posMap.bl;

      // Size: default (40px), compact (36px), slim (32px)
      const sizeMap = { "default": { dim: 40, icon: 18 }, compact: { dim: 36, icon: 16 }, slim: { dim: 32, icon: 16 } };
      const fabSize = sizeMap[this.size] || sizeMap["default"];

      const isRight = this.position === "br" || this.position === "tr";
      const isTop = this.position === "tl" || this.position === "tr";
      const panelStyle = isRight
        ? `${isTop ? 'top' : 'bottom'}:${fabSize.dim + 42}px;right:24px;`
        : `${isTop ? 'top' : 'bottom'}:${fabSize.dim + 42}px;left:24px;`;
      const toastStyle = isRight
        ? `${isTop ? 'top' : 'bottom'}:${fabSize.dim + 42}px;right:24px;`
        : `${isTop ? 'top' : 'bottom'}:${fabSize.dim + 42}px;left:24px;`;

      root.innerHTML = `
        <div class="rm-dock" id="rm-dock" role="group" aria-label="Markup tools" style="${fabPos}--rm-accent:${accentBg};--rm-accent-hover:${accentBgHover};--rm-control-size:${fabSize.dim}px">
        <button type="button" class="rm-fab" id="rm-fab" style="width:${fabSize.dim}px;height:${fabSize.dim}px;${this.fabVisible ? "" : "display:none;"}" title="Expand markup tools" aria-label="Expand markup tools" aria-expanded="false" aria-controls="rm-dock-controls" aria-pressed="false">
          <svg viewBox="0 0 24 24" style="width:${fabSize.icon}px;height:${fabSize.icon}px;fill:none;stroke:currentColor;stroke-width:2;stroke-linecap:round;stroke-linejoin:round;"><path d="M16 3l5 5M4 15L16 3l5 5L9 20l-6 1 1-6z"/></svg>
        </button>
        <div id="rm-dock-controls" class="rm-dock-controls" hidden>
        <button type="button" class="rm-panel-toggle" id="rm-panel-toggle" aria-expanded="false" title="View annotations" aria-label="View annotations" aria-controls="rm-panel">
          <svg viewBox="0 0 24 24"><path d="M4 6h16M4 12h16M4 18h7"/></svg>
          <span class="rm-panel-toggle-badge" id="rm-panel-toggle-badge"></span>
        </button>
        <button type="button" class="rm-toolbar-settings" id="rm-settings-toggle"  title="Toolbar settings" aria-label="Toolbar settings" aria-expanded="false" aria-controls="rm-settings-panel">
          <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M9 3h6l1 3 3 1 2 5-2 5-3 1-1 3H9l-1-3-3-1-2-5 2-5 3-1 1-3z"/><circle cx="12" cy="12" r="3"/></svg>
        </button>
          <button type="button" class="rm-dock-close" id="rm-dock-close" title="Collapse markup tools" aria-label="Collapse markup tools"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M6 6l12 12M18 6L6 18"/></svg></button>
        </div>
        </div>
        <div class="rm-toast-container" id="rm-toast-container" style="${toastStyle}"></div>
        <div class="rm-popup" id="rm-popup" role="dialog" aria-label="Add annotation" aria-modal="false">
          <h3 class="rm-popup-heading">Leave feedback</h3>
          <div style="margin-bottom:12px">
            <p class="rm-popup-el" id="rm-popup-el"></p>
            <p class="rm-popup-text" id="rm-popup-text"></p>
          </div>
          <details class="rm-image-options" id="rm-image-options" ${this.enableScreenshots ? "" : "hidden"}><summary>Attach image</summary>
          <div id="rm-screenshot-actions" class="rm-screenshot-actions">
            <button type="button" id="rm-attach-screen">Capture tab</button>
            <button type="button" id="rm-attach-file">Upload image</button>
            <button type="button" id="rm-remove-screenshot" hidden>Remove image</button>
            <input type="file" id="rm-screenshot-file" accept="image/png,image/jpeg,image/webp" hidden>
            <span id="rm-screenshot-status" role="status">Optional · capture, upload, or paste an image</span>
          </div>
          </details>
          <textarea id="rm-popup-input" rows="3" placeholder="What should change?" aria-label="What should change?"></textarea>
          <details class="rm-image-options"><summary>Type & priority</summary>
          <div style="display:flex;align-items:center;gap:8px;margin-top:8px">
            ${this._menuMarkup({ inputId: "rm-intent-select", label: "Intent", value: "change", options: this._intentOptions() })}
            ${this._menuMarkup({ inputId: "rm-severity-select", label: "Severity", value: "suggestion", options: this._severityOptions() })}
            <span class="rm-count" id="rm-char-count"></span>
          </div>
          </details>
          <div class="rm-popup-actions">
            <button class="rm-btn-cancel" id="rm-btn-cancel">Cancel</button>
            <button class="rm-btn-submit" id="rm-btn-submit" style="background:${accentBg}">
              <span id="rm-submit-label">Add</span>
              <kbd>⌘↩</kbd>
            </button>
          </div>
        </div>
        <div class="rm-panel" id="rm-panel" style="${panelStyle}" role="dialog" aria-label="Annotations panel">
          <div class="rm-panel-header">
            <div style="display:flex;align-items:center;gap:8px">
              <h3>Feedback</h3>
              <span class="rm-panel-count" id="rm-panel-count" style="background:${accentLight};color:${accentText}">0</span>
            </div>
            <div class="rm-panel-header-actions">
              <button class="rm-panel-close" id="rm-panel-close" aria-label="Close annotations panel">
                <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M6 18L18 6M6 6l12 12"/></svg>
              </button>
            </div>
          </div>
          <div class="rm-settings" id="rm-settings-panel" hidden>
            ${this._toolbarSettingsMarkup()}
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
      this.dockState = this.fabVisible ? "collapsed" : "expanded";
      this._renderDockState();
      // Pins container lives on body (not inside fixed root); scroll listener keeps them stuck to target elements
      const pinsContainer = document.createElement("div");
      pinsContainer.className = "rm-pins-container";
      pinsContainer.id = "rm-pins-container";
      document.body.appendChild(pinsContainer);
      if (!this._onResize) {
        this._onResize = this._debouncedRepositionPins(250);
        this._onScroll = this._debouncedRepositionPins(50);
        window.addEventListener("resize", this._onResize);
        window.addEventListener("scroll", this._onScroll, { passive: true });
      }
    },
  });

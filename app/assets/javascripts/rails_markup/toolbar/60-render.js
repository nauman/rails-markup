  Object.assign(RailsMarkupToolbar, {
    _showPopup(x, y) {
      const popup = document.getElementById("rm-popup");
      // Clean up previous drawing elements
      const oldContainer = popup.querySelector(".rm-drawing-container");
      if (oldContainer) oldContainer.remove();
      const oldTools = popup.querySelector("[data-draw]");
      if (oldTools) { const p = oldTools.parentElement; if (p && !p.classList.contains("rm-popup-actions")) p.remove(); }
      this.drawingCanvas = null;
      this.drawingCtx = null;
      this.drawingHistory = [];
      this.drawingMode = null;
      this._screenshotImg = null;

      document.getElementById("rm-image-options").open = Boolean(this._currentScreenshot);
      this._resetScreenshotStatus();
      popup.style.display = "block";
      popup.style.opacity = "0";
      popup.style.left = "-9999px";
      popup.style.top = "-9999px";
      popup.style.width = this._currentScreenshot ? "480px" : "360px";
      const pw = popup.offsetWidth || (this._currentScreenshot ? 480 : 360);
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
      this._setMenuValue(document.getElementById("rm-intent-select"), "change", false);
      this._setMenuValue(document.getElementById("rm-severity-select"), "suggestion", false);
      document.getElementById("rm-char-count").textContent = "";
      document.getElementById("rm-submit-label").textContent = "Add";
      this._closeAllMenus();

      // Show screenshot preview with drawing tools
      if (this._currentScreenshot) {
        this._initDrawing(this._currentScreenshot);
      }

      setTimeout(() => input.focus(), 50);
    },
    _closePopup() {
      this._closeAllMenus();
      const popup = document.getElementById("rm-popup");
      popup.style.transition = "opacity 0.15s ease";
      popup.style.opacity = "0";
      setTimeout(() => { popup.style.display = "none"; popup.style.transition = ""; popup.style.opacity = ""; popup.style.width = ""; }, 150);
      document.getElementById("rm-popup-input").value = "";
      this.selectedText = null;
      this._currentElement = null;
      this._currentScreenshot = null;
      this.drawingCanvas = null;
      this.drawingCtx = null;
      this.drawingHistory = [];
      this.drawingMode = null;
      this._screenshotImg = null;
      this.editingId = null;
      document.getElementById("rm-submit-label").textContent = "Add";
    },
    _updateCharCount() {
      const len = document.getElementById("rm-popup-input").value.length;
      const el = document.getElementById("rm-char-count");
      el.textContent = len > 0 ? len : "";
      el.style.color = len > 500 ? "#b91c1c" : "#596579";
    },
    submitAnnotation(event) {
      if (event) event.preventDefault();
      const comment = document.getElementById("rm-popup-input").value.trim();
      if (!comment) return;
      const intent = document.getElementById("rm-intent-select").value;
      const severity = document.getElementById("rm-severity-select").value;

      // If drawing canvas exists, merge drawings onto screenshot
      const screenshot = this._mergeDrawing() || this._currentScreenshot;

      // Edit existing annotation
      if (this.editingId) {
        const existing = this.annotations.find(a => a.id === this.editingId);
        if (existing) {
          const dirtyFields = [];
          if (existing.comment !== comment) dirtyFields.push("content");
          if (existing.intent !== intent) dirtyFields.push("intent");
          if (existing.severity !== severity) dirtyFields.push("severity");
          if (screenshot && existing.screenshot !== screenshot) dirtyFields.push("metadata");
          const committed = dirtyFields.length === 0 || this._persistLocalMutation("upsert", dirtyFields, () => {
            existing.comment = comment;
            existing.intent = intent;
            existing.severity = severity;
            if (screenshot) existing.screenshot = screenshot;
            return existing;
          });
          if (!committed) return;
          this._rebuildList();
          this._closePopup();
          return;
        }
      }

      // New annotation
      const annotation = {
        id: this.nextId,
        clientId: this._newClientId(),
        serverId: null,
        serverRevision: 0,
        syncState: "pending",
        serverUpdatedAt: null,
        dirtyFields: [],
        revision: 0,
        comment, intent, severity,
        element: this._currentElement,
        selectedText: this.selectedText || null,
        screenshot: screenshot || null,
        url: window.location.href,
        pathname: this._pageUrl(),
        pageUrl: this._pageUrl(),
        timestamp: new Date().toISOString(),
        status: "pending",
        thread: []
      };

      const committed = this._persistLocalMutation("upsert", this._browserCreateFields(), () => {
        this.nextId += 1;
        this.annotations.push(annotation);
        return annotation;
      });
      if (!committed) return;
      this._renderPin(annotation);
      // Rebuild (not append) so a new card honors the active panel filter —
      // e.g. a pending annotation must not show while "Resolved" is selected.
      this._rebuildList();
      this._updateCount();
      this._closePopup();
    },
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
          chip.style.color = "#596579";
        }
      });
    },
    _filteredAnnotations() {
      if (this.activeFilter === "all") return this.annotations;
      if (this.activeFilter === "pending") return this.annotations.filter(a => a.status === "pending" || a.status === "acknowledged");
      if (this.activeFilter === "resolved") return this.annotations.filter(a => a.status === "resolved" || a.status === "dismissed");
      return this.annotations;
    },
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
          <span style="margin-left:auto;display:flex;gap:2px;align-items:center;">
            ${this._menuMarkup({
              statusId: annotation.id,
              label: "Change status",
              value: annotation.status,
              options: this._statusOptions(),
              compact: true
            })}
            <button data-edit-id="${annotation.id}" title="Edit" style="padding:2px 4px;background:none;border:none;cursor:pointer;color:#64748b;border-radius:4px;display:flex;align-items:center;" onmouseover="this.style.color='#6b7280'" onmouseout="this.style.color='#64748b'">
              <svg viewBox="0 0 24 24" style="width:14px;height:14px;fill:none;stroke:currentColor;stroke-width:2;stroke-linecap:round;stroke-linejoin:round;"><path d="M17 3a2.85 2.85 0 114 4L7.5 20.5 2 22l1.5-5.5Z"/><path d="m15 5 4 4"/></svg>
            </button>
            <button data-delete-id="${annotation.id}" title="Delete" style="padding:2px 4px;background:none;border:none;cursor:pointer;color:#64748b;border-radius:4px;display:flex;align-items:center;" onmouseover="this.style.color='#ef4444'" onmouseout="this.style.color='#64748b'">
              <svg viewBox="0 0 24 24" style="width:14px;height:14px;fill:none;stroke:currentColor;stroke-width:2;stroke-linecap:round;stroke-linejoin:round;"><path d="M18 6 6 18"/><path d="m6 6 12 12"/></svg>
            </button>
          </span>
        </div>
        <div class="rm-card-body">${this._esc(annotation.comment)}</div>
        <div class="rm-card-path">${this._esc(annotation.pathname || "")} &rsaquo; ${this._esc(annotation.element?.selector || "")}</div>
        ${annotation.selectedText ? '<div class="rm-card-path" style="font-style:italic">"' + this._esc(annotation.selectedText.slice(0, 60)) + '"</div>' : ''}
        ${threadHtml}
      `;

      list.appendChild(card);
    },
    _rebuildList() {
      const list = document.getElementById("rm-panel-list");
      if (!list) return;
      this._closeAllMenus();
      list.innerHTML = "";
      this._renderStorageError(list);
      this._renderFailedSync(list);
      const filtered = this._filteredAnnotations();
      if (filtered.length === 0) {
        const empty = document.createElement("div");
        empty.className = "rm-empty";
        empty.innerHTML = '<div class="rm-empty-icon">&#9670;</div><div class="rm-empty-text">No annotations yet</div>';
        list.appendChild(empty);
        return;
      }
      filtered.forEach(a => this._renderCard(a));
    },
    _renderStorageError(list) {
      if (!this._storageError) return;
      const error = document.createElement("div");
      error.className = "rm-storage-error";
      error.setAttribute("role", "alert");
      error.style.cssText = "padding:8px;margin-bottom:8px;border:1px solid #fecaca;border-radius:8px;background:#fef2f2;color:#991b1b;font-size:11px;";
      error.textContent = this._storageError;
      list.appendChild(error);
    },
    _renderFailedSync(list) {
      const failed = Object.values(this.outbox || {}).filter(entry => entry?.syncState === "failed");
      if (failed.length === 0) return;
      const section = document.createElement("div");
      section.className = "rm-failed-sync";
      section.setAttribute("role", "status");
      failed.forEach(entry => {
        const item = document.createElement("div");
        item.style.cssText = "display:flex;align-items:center;gap:8px;padding:8px;margin-bottom:8px;border:1px solid #fecaca;border-radius:8px;background:#fef2f2;color:#991b1b;font-size:11px;";
        const label = entry.type === "delete" ? "Delete failed" : "Sync failed";
        item.innerHTML = `<span style="flex:1">${label}</span><button type="button" data-retry-client-id="${this._esc(entry.clientId)}" style="border:1px solid #fca5a5;border-radius:6px;background:#fff;padding:3px 7px;color:#991b1b;cursor:pointer">Retry</button>`;
        section.appendChild(item);
      });
      list.appendChild(section);
    },
    _editAnnotation(id) {
      const annotation = this.annotations.find(a => a.id === id);
      if (!annotation) return;
      this.editingId = id;
      this._currentElement = annotation.element;
      this.selectedText = annotation.selectedText;
      this._currentScreenshot = annotation.screenshot || null;

      // Pre-fill popup fields
      document.getElementById("rm-popup-el").textContent = annotation.element?.selector || "";
      document.getElementById("rm-popup-text").textContent = annotation.selectedText
        ? '"' + annotation.selectedText.slice(0, 60) + '"'
        : (annotation.element?.nearbyText || "").slice(0, 60);
      document.getElementById("rm-popup-input").value = annotation.comment;
      this._setMenuValue(document.getElementById("rm-intent-select"), annotation.intent, false);
      this._setMenuValue(document.getElementById("rm-severity-select"), annotation.severity, false);
      document.getElementById("rm-submit-label").textContent = "Save";
      this._updateCharCount();
      this._closeAllMenus();

      // Clean up previous drawing elements
      const popup = document.getElementById("rm-popup");
      const oldContainer = popup.querySelector(".rm-drawing-container");
      if (oldContainer) oldContainer.remove();
      const oldTools = popup.querySelector("[data-draw]");
      if (oldTools) { const p = oldTools.parentElement; if (p && !p.classList.contains("rm-popup-actions")) p.remove(); }
      this.drawingCanvas = null;
      this.drawingCtx = null;
      this.drawingHistory = [];
      this.drawingMode = null;
      this._screenshotImg = null;

      // Position popup centered on screen
      popup.style.display = "block";
      popup.style.width = this._currentScreenshot ? "480px" : "360px";
      const pw = popup.offsetWidth || 360;
      const ph = popup.offsetHeight || 300;
      popup.style.left = Math.max(10, Math.round((window.innerWidth - pw) / 2)) + "px";
      popup.style.top = Math.max(10, Math.round((window.innerHeight - ph) / 2)) + "px";
      popup.style.opacity = "1";

      if (this._currentScreenshot) {
        this._initDrawing(this._currentScreenshot);
      }

      setTimeout(() => document.getElementById("rm-popup-input").focus(), 50);
    },
    _changeStatus(id, newStatus) {
      const annotation = this.annotations.find(a => a.id === id);
      if (!annotation) return;
      const committed = this._persistLocalMutation("upsert", ["status"], () => {
        annotation.status = newStatus;
        return annotation;
      });
      if (!committed) return;
      this._renderPins();
      this._rebuildList();
      const label = newStatus.charAt(0).toUpperCase() + newStatus.slice(1);
      this._showToast(`#${id} marked as ${label}`, newStatus === "resolved" ? "resolved" : "dismissed");
    },
    _deleteAnnotation(id) {
      const idx = this.annotations.findIndex(a => a.id === id);
      if (idx === -1) return;
      const committed = this._persistLocalMutation("delete", [], () => this.annotations.splice(idx, 1)[0]);
      if (!committed) return;
      this._renderPins();
      this._rebuildList();
      this._updateCount();
    },
    _updateCount() {
      const count = this.annotations.length;
      const countEl = document.getElementById("rm-panel-count");
      if (countEl) countEl.textContent = count;
      const badge = document.getElementById("rm-panel-toggle-badge");
      if (badge) {
        if (count > 0) { badge.textContent = count; badge.style.display = "flex"; }
        else { badge.style.display = "none"; }
      }
      const toggle = document.getElementById("rm-panel-toggle");
      if (toggle) toggle.style.display = "flex";
    },
    _renderPin(annotation) {
      if (!annotation.element?.boundingBox) return;
      const { top, left, width } = annotation.element.boundingBox;
      const container = document.getElementById("rm-pins-container");
      if (!container) return;
      const isResolved = annotation.status === "resolved" || annotation.status === "dismissed";
      const pin = document.createElement("div");
      pin.className = "rm-pin" + (isResolved ? "" : " rm-pin-active");
      pin.dataset.pinId = annotation.id;
      this._positionPin(pin, { top, left, width });
      pin.style.background = isResolved ? "#d1d5db" : this._accentBg();
      if (isResolved) pin.style.opacity = "0.6";
      pin.textContent = annotation.id;
      pin.title = "#" + annotation.id + ": " + annotation.comment.slice(0, 50);
      container.appendChild(pin);
    },
    _positionPin(pin, { top, left, width }) {
      const viewportWidth = document.documentElement.clientWidth || window.innerWidth;
      const scrollLeft = window.scrollX || 0;
      // The 20px pin must fit inside the viewport, including its focus/hover space.
      const minLeft = scrollLeft + 4;
      const maxLeft = Math.max(minLeft, scrollLeft + viewportWidth - 24);
      pin.style.left = Math.max(minLeft, Math.min(left + width - 10, maxLeft)) + "px";
      pin.style.top = Math.max(4, top - 10) + "px";
    },
    _renderPins() {
      const container = document.getElementById("rm-pins-container");
      if (container) container.innerHTML = "";
      // Only render pins for annotations on the current page
      const currentPath = this._pageUrl();
      this.annotations
        .filter(a => (a.pageUrl || a.pathname) === currentPath)
        .forEach(a => this._renderPin(a));
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
        if (pin) this._positionPin(pin, annotation.element.boundingBox);
      });
    },
    _debouncedRepositionPins(delay = 250) {
      let timer = null;
      return () => { if (timer) clearTimeout(timer); timer = setTimeout(() => this._repositionPins(), delay); };
    },
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
    _updateStatus() {
      const dot = document.getElementById("rm-status-dot");
      const text = document.getElementById("rm-status-text");
      if (dot) {
        dot.style.background = this.serverOnline ? "#4ade80" : "#d1d5db";
        dot.style.boxShadow = this.serverOnline ? "0 0 0 2px rgba(74,222,128,0.2)" : "";
      }
      if (text) text.textContent = this.serverOnline ? "Connected" : (this._syncUnavailable || "Offline");
    },
    _validToolbarAccent(value) {
      return ["indigo", "amber", "blue", "emerald", "rose"].includes(value);
    },
    _validToolbarPosition(value) {
      return ["bl", "br", "tl", "tr"].includes(value);
    },
    _validToolbarSize(value) {
      return ["slim", "compact", "default"].includes(value);
    },
    _toolbarSettingOptions(setting) {
      switch (setting) {
      case "accent":
        return [
          ["indigo", "Indigo"],
          ["amber", "Amber"],
          ["blue", "Blue"],
          ["emerald", "Emerald"],
          ["rose", "Rose"]
        ];
      case "position":
        return [
          ["bl", "Bottom-left"],
          ["br", "Bottom-right"],
          ["tl", "Top-left"],
          ["tr", "Top-right"]
        ];
      case "size":
        return [
          ["default", "Default"],
          ["compact", "Compact"],
          ["slim", "Slim"]
        ];
      case "fabVisible":
      case "enableScreenshots":
        return [
          [true, "On"],
          [false, "Off"]
        ];
      default:
        return [];
      }
    },
    _toolbarSettingLabel(setting) {
      switch (setting) {
      case "accent": return "Accent";
      case "position": return "Position";
      case "size": return "Size";
      case "fabVisible": return "Show floating toolbar";
      case "enableScreenshots": return "Image attachments";
      default: return setting;
      }
    },
    _toolbarSettingCurrentValue(setting) {
      switch (setting) {
      case "accent": return this.accent;
      case "position": return this.position;
      case "size": return this.size;
      case "fabVisible": return this.fabVisible;
      case "enableScreenshots": return this.enableScreenshots;
      default: return null;
      }
    },
    _toolbarSettingDisplayValue(value) {
      return value === true ? "true" : value === false ? "false" : String(value);
    },
    _toolbarSettingsMarkup() {
      return [
        "accent",
        "position",
        "size",
        "fabVisible",
        "enableScreenshots"
      ].map(setting => this._toolbarSettingsRowMarkup(setting)).join("");
    },
    _toolbarSettingsRowMarkup(setting) {
      const current = this._toolbarSettingCurrentValue(setting);
      const options = this._toolbarSettingOptions(setting);
      const label = this._toolbarSettingLabel(setting);
      if (typeof current === "boolean") {
        return `<div class="rm-settings-group rm-settings-switch-row"><span class="rm-settings-label">${this._esc(label)}</span><button type="button" class="rm-setting-switch" role="switch" aria-label="${this._esc(label)}" aria-checked="${current}" data-setting="${setting}" data-value="${!current}"><span></span></button></div>`;
      }
      const colors = { indigo: "#4f46e5", amber: "#f59e0b", blue: "#2563eb", emerald: "#059669", rose: "#e11d48" };
      const corners = { bl: "◱", br: "◲", tl: "◰", tr: "◳" };
      const buttons = options.map(([value, optionLabel]) => {
        const active = String(value) === String(current);
        const swatch = setting === "accent";
        const content = swatch ? (active ? "✓" : "") : setting === "position" ? corners[value] : this._esc(optionLabel);
        return `<button type="button" class="rm-setting-choice${swatch ? " rm-color-swatch" : ""}${setting === "position" ? " rm-corner-choice" : ""}" data-setting="${setting}" data-value="${this._esc(this._toolbarSettingDisplayValue(value))}" aria-label="${this._esc(optionLabel)}" title="${this._esc(optionLabel)}" aria-pressed="${active}"${swatch ? ` style="background:${colors[value]}"` : ""}>${content}</button>`;
      }).join("");
      return `<div class="rm-settings-group"><div class="rm-settings-label">${this._esc(label)}</div><div class="rm-settings-options" role="group" aria-label="${this._esc(label)}">${buttons}</div></div>`;
    },
    _toolbarSettingValue(setting, rawValue) {
      if (setting === "fabVisible" || setting === "enableScreenshots") {
        return rawValue === true || rawValue === "true";
      }
      return String(rawValue || "");
    },
    _setToolbarSetting(setting, rawValue) {
      const value = this._toolbarSettingValue(setting, rawValue);
      const next = Object.assign({}, this.toolbarSettings, { [setting]: value });
      const normalized = this._normalizeToolbarSettings(next);
      if (JSON.stringify(normalized) === JSON.stringify(this.toolbarSettings)) return;
      if (!this._saveToolbarSettings(normalized)) return;
      const settingsOpen = this._settingsPanelOpen;
      this.toolbarSettings = normalized;
      this.destroy();
      this.init(this._bootstrapOptions || {});
      if (settingsOpen && this.fabVisible) {
        this._toggleSettings();
        this.root.querySelector(`[data-setting="${setting}"][aria-pressed="true"], [data-setting="${setting}"][role="switch"]`)?.focus();
      }
    },
    _toggleSettings() {
      const panel = document.getElementById("rm-settings-panel");
      const toggle = document.getElementById("rm-settings-toggle");
      if (!panel) return;
      this._expandDock();
      const feedback = document.getElementById("rm-panel");
      const opening = panel.hidden || feedback.style.display !== "flex";
      feedback.style.display = opening ? "flex" : "none";
      feedback.dataset.view = opening ? "settings" : "feedback";
      feedback.querySelector("h3").textContent = opening ? "Toolbar settings" : "Feedback";
      panel.hidden = !opening;
      this._settingsPanelOpen = opening;
      document.getElementById("rm-panel-toggle").setAttribute("aria-expanded", "false");
      if (toggle) toggle.setAttribute("aria-expanded", String(opening));
    },
    _resetScreenshotStatus(message = "Optional · capture, upload, or paste an image") {
      document.getElementById("rm-screenshot-status").textContent = message;
      document.getElementById("rm-remove-screenshot").hidden = !this._currentScreenshot;
    },
    _removeScreenshot() {
      this._currentScreenshot = null;
      this.root.querySelector(".rm-drawing-container")?.remove();
      const tool = this.root.querySelector("[data-draw]");
      tool?.parentElement.remove();
      this.drawingCanvas = null;
      this.drawingCtx = null;
      this.drawingHistory = [];
      this._screenshotImg = null;
      document.getElementById("rm-screenshot-file").value = "";
      this._resetScreenshotStatus();
    },
    _useScreenshot(dataUrl) {
      if (document.getElementById("rm-popup").style.display !== "block") return;
      this._removeScreenshot();
      this._currentScreenshot = dataUrl;
      document.getElementById("rm-image-options").open = true;
      this._initDrawing(dataUrl);
      this._resetScreenshotStatus("Image attached · review before submitting");
    },
    async _attachScreenshotFile(file) {
      if (!file) return;
      if (!["image/png", "image/jpeg", "image/webp"].includes(file.type) || file.size > 5 * 1024 * 1024) {
        this._resetScreenshotStatus("Choose a PNG, JPEG, or WebP under 5 MB.");
        return;
      }
      const popup = document.getElementById("rm-popup");
      const reader = new FileReader();
      reader.onload = () => { if (popup === document.getElementById("rm-popup")) this._useScreenshot(reader.result); };
      reader.onerror = () => this._resetScreenshotStatus("Could not read this image. Try another file.");
      reader.readAsDataURL(file);
    },
    async _attachScreen() {
      if (!navigator.mediaDevices?.getDisplayMedia) {
        this._resetScreenshotStatus("Tab capture is unavailable here. Upload or paste an image instead.");
        return;
      }
      let stream;
      let video;
      let frameTimeout;
      const popup = document.getElementById("rm-popup");
      const button = document.getElementById("rm-attach-screen");
      button.disabled = true;
      this._resetScreenshotStatus("Choose a tab or window in the browser prompt. You can also upload an image.");
      try {
        // Must run directly from the user's click to retain browser activation.
        stream = await navigator.mediaDevices.getDisplayMedia({ video: true, audio: false, preferCurrentTab: true });
        video = document.createElement("video");
        video.srcObject = stream;
        video.muted = true;
        await Promise.race([
          video.play(),
          new Promise((_, reject) => { frameTimeout = setTimeout(() => reject(new Error("Capture timed out")), 8000); })
        ]);
        if (popup !== document.getElementById("rm-popup") || popup.style.display !== "block") return;
        this._removeHighlight();
        this.root.style.visibility = "hidden";
        await new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)));
        const scale = Math.min(1, 1600 / Math.max(video.videoWidth, video.videoHeight));
        const canvas = document.createElement("canvas");
        canvas.width = Math.round(video.videoWidth * scale);
        canvas.height = Math.round(video.videoHeight * scale);
        if (!canvas.width || !canvas.height) throw new Error("No video frame");
        canvas.getContext("2d").drawImage(video, 0, 0, canvas.width, canvas.height);
        this._useScreenshot(canvas.toDataURL("image/png"));
      } catch (error) {
        this._resetScreenshotStatus(error.name === "NotAllowedError" ? "Capture cancelled. You can upload or paste an image." : "Could not capture this tab. Upload or paste an image instead.");
      } finally {
        clearTimeout(frameTimeout);
        stream?.getTracks().forEach(track => track.stop());
        if (video) video.srcObject = null;
        this.root.style.visibility = "";
        button.disabled = false;
      }
    },
    _initDrawing(screenshotDataUrl) {
      const popup = document.getElementById("rm-popup");
      let container = popup.querySelector(".rm-drawing-container");
      if (container) container.remove();

      container = document.createElement("div");
      container.className = "rm-drawing-container";
      container.style.cssText = "position:relative;margin-bottom:12px;border-radius:8px;overflow:hidden;border:1px solid #e5e7eb;";

      const img = new Image();
      img.src = screenshotDataUrl;
      img.style.cssText = "display:block;width:100%;height:auto;border-radius:8px;";
      container.appendChild(img);

      const canvas = document.createElement("canvas");
      canvas.style.cssText = "position:absolute;top:0;left:0;width:100%;height:100%;cursor:crosshair;";
      container.appendChild(canvas);

      // Tool buttons
      const tools = document.createElement("div");
      tools.className = "rm-drawing-tools";
      tools.style.cssText = "display:flex;gap:4px;padding:6px 0;";
      tools.innerHTML = `
        <button type="button" data-draw="arrow" class="rm-pill" style="font-size:11px;padding:4px 10px;">Arrow</button>
        <button type="button" data-draw="rect" class="rm-pill" style="font-size:11px;padding:4px 10px;">Rect</button>
        <button type="button" data-draw="highlight" class="rm-pill" style="font-size:11px;padding:4px 10px;">Highlight</button>
        <button type="button" data-draw="undo" class="rm-pill" style="font-size:11px;padding:4px 10px;margin-left:auto;">Undo</button>
      `;

      const textarea = popup.querySelector("textarea");
      popup.insertBefore(tools, textarea);
      popup.insertBefore(container, tools);

      this._resetScreenshotStatus("Image attached · review before submitting");
      img.onerror = () => {
        this._removeScreenshot();
        this._resetScreenshotStatus("Could not open this image. Try another file.");
      };
      img.onload = () => {
        canvas.width = img.naturalWidth || img.offsetWidth;
        canvas.height = img.naturalHeight || img.offsetHeight;
        this.drawingCanvas = canvas;
        this.drawingCtx = canvas.getContext("2d");
        this._screenshotImg = img;
        this.drawingHistory = [];
        this.drawingMode = null;
        this._bindDrawingEvents(canvas, tools);
      };
    },
    _bindDrawingEvents(canvas, tools) {
      const self = this;
      let isDrawing = false;
      let points = [];

      tools.addEventListener("click", (e) => {
        const btn = e.target.closest("[data-draw]");
        if (!btn) return;
        const mode = btn.dataset.draw;
        if (mode === "undo") {
          self._undoDrawing();
          return;
        }
        self.drawingMode = mode;
        tools.querySelectorAll("[data-draw]").forEach(b => {
          b.style.background = b.dataset.draw === mode ? self._accentBg() : "#fff";
          b.style.color = b.dataset.draw === mode ? "#fff" : "#374151";
        });
      });

      const getPos = (e) => {
        const rect = canvas.getBoundingClientRect();
        return {
          x: (e.clientX - rect.left) * (canvas.width / rect.width),
          y: (e.clientY - rect.top) * (canvas.height / rect.height)
        };
      };

      canvas.addEventListener("mousedown", (e) => {
        if (!self.drawingMode) return;
        e.stopPropagation();
        isDrawing = true;
        self.drawingStart = getPos(e);
        points = [self.drawingStart];
      });

      canvas.addEventListener("mousemove", (e) => {
        if (!isDrawing || !self.drawingMode) return;
        e.stopPropagation();
        const pos = getPos(e);
        if (self.drawingMode === "highlight") {
          points.push(pos);
          self._redrawCanvas();
          self._drawHighlightPath(points);
        } else {
          self._redrawCanvas();
          self._drawShape(self.drawingMode, self.drawingStart, pos);
        }
      });

      canvas.addEventListener("mouseup", (e) => {
        if (!isDrawing || !self.drawingMode) return;
        e.stopPropagation();
        isDrawing = false;
        const end = getPos(e);
        if (self.drawingMode === "highlight") {
          self.drawingHistory.push({ type: "highlight", points: [...points] });
        } else {
          self.drawingHistory.push({ type: self.drawingMode, start: self.drawingStart, end: end });
        }
        self._redrawCanvas();
        points = [];
      });
    },
    _drawShape(type, start, end) {
      const ctx = this.drawingCtx;
      if (!ctx) return;
      ctx.lineWidth = 3;

      if (type === "arrow") {
        ctx.strokeStyle = "#ef4444";
        ctx.beginPath();
        ctx.moveTo(start.x, start.y);
        ctx.lineTo(end.x, end.y);
        ctx.stroke();
        // Arrowhead
        const angle = Math.atan2(end.y - start.y, end.x - start.x);
        const headLen = 12;
        ctx.beginPath();
        ctx.moveTo(end.x, end.y);
        ctx.lineTo(end.x - headLen * Math.cos(angle - Math.PI / 6), end.y - headLen * Math.sin(angle - Math.PI / 6));
        ctx.moveTo(end.x, end.y);
        ctx.lineTo(end.x - headLen * Math.cos(angle + Math.PI / 6), end.y - headLen * Math.sin(angle + Math.PI / 6));
        ctx.stroke();
      } else if (type === "rect") {
        ctx.strokeStyle = "#ef4444";
        ctx.strokeRect(start.x, start.y, end.x - start.x, end.y - start.y);
      }
    },
    _drawHighlightPath(points) {
      const ctx = this.drawingCtx;
      if (!ctx || points.length < 2) return;
      ctx.strokeStyle = "rgba(250,204,21,0.5)";
      ctx.lineWidth = 16;
      ctx.lineCap = "round";
      ctx.lineJoin = "round";
      ctx.beginPath();
      ctx.moveTo(points[0].x, points[0].y);
      for (let i = 1; i < points.length; i++) {
        ctx.lineTo(points[i].x, points[i].y);
      }
      ctx.stroke();
      ctx.lineWidth = 3;
    },
    _redrawCanvas() {
      const ctx = this.drawingCtx;
      if (!ctx) return;
      ctx.clearRect(0, 0, this.drawingCanvas.width, this.drawingCanvas.height);
      this.drawingHistory.forEach(shape => {
        if (shape.type === "highlight") {
          this._drawHighlightPath(shape.points);
        } else {
          this._drawShape(shape.type, shape.start, shape.end);
        }
      });
    },
    _undoDrawing() {
      if (this.drawingHistory.length === 0) return;
      this.drawingHistory.pop();
      this._redrawCanvas();
    },
    _mergeDrawing() {
      if (!this.drawingCanvas || !this._screenshotImg || this.drawingHistory.length === 0) return null;
      try {
        const merged = document.createElement("canvas");
        merged.width = this.drawingCanvas.width;
        merged.height = this.drawingCanvas.height;
        const ctx = merged.getContext("2d");
        ctx.drawImage(this._screenshotImg, 0, 0, merged.width, merged.height);
        ctx.drawImage(this.drawingCanvas, 0, 0);
        return merged.toDataURL("image/png", 0.7);
      } catch {
        return null;
      }
    },
    _fabIconSize() {
      const map = { "default": 20, compact: 18, slim: 16 };
      return map[this.size] || 20;
    },
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
    _esc(str) {
      const div = document.createElement("div");
      div.textContent = str || "";
      return div.innerHTML;
    }
  });

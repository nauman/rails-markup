  Object.assign(RailsMarkupToolbar, {
    _bindEvents() {
      const self = this;
      document.getElementById("rm-attach-screen").addEventListener("click", () => self._attachScreen());
      document.getElementById("rm-attach-file").addEventListener("click", () => document.getElementById("rm-screenshot-file").click());
      document.getElementById("rm-screenshot-file").addEventListener("change", e => self._attachScreenshotFile(e.target.files[0]));
      document.getElementById("rm-remove-screenshot").addEventListener("click", () => self._removeScreenshot());
      document.getElementById("rm-popup-input").addEventListener("paste", e => {
        if (!self.enableScreenshots) return;
        const file = Array.from(e.clipboardData?.items || []).find(item => item.type.startsWith("image/"))?.getAsFile();
        if (file) { e.preventDefault(); self._attachScreenshotFile(file); }
      });
      document.getElementById("rm-fab").addEventListener("click", () => self.dockState === "collapsed" ? self._expandDock() : self.toggleMode());
      document.getElementById("rm-dock-close").addEventListener("click", () => self.active ? self._deactivateMode() : self._collapseDock());
      document.getElementById("rm-panel-toggle").addEventListener("click", () => self.togglePanel());
      document.getElementById("rm-panel-close").addEventListener("click", () => self._settingsPanelOpen ? self._toggleSettings() : self.togglePanel());
      document.getElementById("rm-settings-toggle").addEventListener("click", () => self._toggleSettings());
      document.getElementById("rm-btn-cancel").addEventListener("click", () => self._closePopup());
      document.getElementById("rm-btn-submit").addEventListener("click", (e) => self.submitAnnotation(e));
      document.getElementById("rm-popup-input").addEventListener("input", () => self._updateCharCount());
      document.getElementById("rm-filter-chips").addEventListener("click", (e) => {
        const chip = e.target.closest("[data-filter]");
        if (chip) self._filterAnnotations(chip.dataset.filter);
      });

      // Custom menus (intent/severity/status) — button+menu, never native selects
      // so host FormSelect/Select2 enhancers cannot rewrite our DOM (#4).
      this.root.addEventListener("click", (e) => {
        const setting = e.target.closest("[data-setting]");
        if (setting) {
          e.preventDefault();
          e.stopPropagation();
          this._setToolbarSetting(setting.dataset.setting, setting.dataset.value);
          return;
        }
        const option = e.target.closest(".rm-menu-option");
        if (option) {
          e.preventDefault();
          e.stopPropagation();
          this._selectMenuOption(option);
          return;
        }
        const btn = e.target.closest(".rm-menu-btn");
        if (btn) {
          e.preventDefault();
          e.stopPropagation();
          const menu = this._menuForElement(btn);
          if (!menu || !this.root.contains(menu)) return;
          this._toggleMenu(menu);
          return;
        }
        if (!this._menuForElement(e.target)) this._closeAllMenus();
      });
      if (!this._boundMenuDocClick) {
        this._boundMenuDocClick = (e) => {
          if (!this.root || this._menuForElement(e.target)) return;
          this._closeAllMenus();
        };
        document.addEventListener("click", this._boundMenuDocClick);
      }

      // Event delegation for cards (status change, edit, delete, or click scrolls to element)
      const panelList = document.getElementById("rm-panel-list");
      if (!this._boundMenuViewportChange) {
        this._boundMenuViewportChange = () => self._closeAllMenus();
        window.addEventListener("resize", this._boundMenuViewportChange);
        window.addEventListener("scroll", this._boundMenuViewportChange, { passive: true });
      }
      panelList.addEventListener("scroll", this._boundMenuViewportChange, { passive: true });
      panelList.addEventListener("click", (e) => {
        const retryBtn = e.target.closest("[data-retry-client-id]");
        if (retryBtn) {
          e.stopPropagation();
          self._retrySync(retryBtn.dataset.retryClientId);
          return;
        }
        // Status menu — leave bubbling for the root menu handler; don't scroll.
        if (e.target.closest(".rm-menu")) return;
        // Edit button
        const editBtn = e.target.closest("[data-edit-id]");
        if (editBtn) {
          e.stopPropagation();
          const id = parseInt(editBtn.dataset.editId, 10);
          self._editAnnotation(id);
          return;
        }
        // Delete button
        const deleteBtn = e.target.closest("[data-delete-id]");
        if (deleteBtn) {
          e.stopPropagation();
          const id = parseInt(deleteBtn.dataset.deleteId, 10);
          self._deleteAnnotation(id);
          return;
        }
        // Card click scrolls to element
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
      if (!this._boundKeyDown) {
        this._boundKeyDown = (e) => self._handleKeyDown(e);
        document.addEventListener("keydown", this._boundKeyDown, true);
      }
      this._boundTouchStart = (e) => { if (self.active && e.touches[0]) { const t = e.touches[0]; const el = document.elementFromPoint(t.clientX, t.clientY); if (el && !self._isToolbar(el) && e.cancelable) e.preventDefault(); self._handleMouseDown({ clientX: t.clientX, clientY: t.clientY }); } };
      this._boundTouchEnd = (e) => { if (self.active && e.changedTouches[0]) { const t = e.changedTouches[0]; const el = document.elementFromPoint(t.clientX, t.clientY); if (el && !self._isToolbar(el)) { e.preventDefault(); self._handleMouseUp({ clientX: t.clientX, clientY: t.clientY, preventDefault(){}, stopPropagation(){} }); } } };

      // Turbo Frames — partial DOM update, reposition pins
      if (!this._boundTurboFrame) {
        this._boundTurboFrame = () => self._onTurboFrameRender();
        document.addEventListener("turbo:frame-render", this._boundTurboFrame);
      }
    },
    _onTurboNavigate() {
      const newPageUrl = this._pageUrl();
      if (newPageUrl === this._currentPageUrl) return; // same page (anchor change, etc.)
      this._currentPathname = window.location.pathname;
      this._currentPageUrl = newPageUrl;

      // Deactivate crosshair mode
      this._deactivateMode();

      // Close popup
      const popup = document.getElementById("rm-popup");
      if (popup && popup.style.display === "block") this._closePopup();

      // Close panel
      const panel = document.getElementById("rm-panel");
      if (panel) panel.style.display = "none";

      document.getElementById("rm-panel-toggle")?.setAttribute("aria-expanded", "false");

      // Rerender pins for current page (annotations are global, pins are page-specific)
      this._renderPins();
      this._updateCount();
      this._rebuildList();

      // Re-init session for new URL
      this._pullNeeded = true;
      if (this.serverOnline) {
        this._synchronizeCurrentPage(true).catch(error => console.warn("[rails-markup] page sync failed:", error));
      }
    },
    _onTurboFrameRender() {
      // Frame content changed — DOM elements may have moved, reposition pins
      this._repositionPins();
    },
    toggleMode() {
      this.active = !this.active;
      if (this.active) {
        this._activateMode();
      } else {
        this._deactivateMode();
      }
    },
    _activateMode() {
      document.body.style.cursor = "crosshair";
      this.active = true;
      this.dockState = "annotating";
      this._renderDockState();
      document.addEventListener("mousemove", this._boundMouseMove, true);
      document.addEventListener("mousedown", this._boundMouseDown, true);
      document.addEventListener("mouseup", this._boundMouseUp, true);
      document.addEventListener("click", this._boundClick, true);
      document.addEventListener("touchstart", this._boundTouchStart, true);
      document.addEventListener("touchend", this._boundTouchEnd, true);
    },
    _deactivateMode() {
      this.active = false;
      document.body.style.cursor = "";
      if (this.dockState === "annotating") this.dockState = "expanded";
      this._renderDockState();
      document.removeEventListener("mousemove", this._boundMouseMove, true);
      document.removeEventListener("mousedown", this._boundMouseDown, true);
      document.removeEventListener("mouseup", this._boundMouseUp, true);
      document.removeEventListener("click", this._boundClick, true);
      document.removeEventListener("touchstart", this._boundTouchStart, true);
      document.removeEventListener("touchend", this._boundTouchEnd, true);
      this._removeHighlight();
    },
    _renderDockState() {
      const dock = document.getElementById("rm-dock");
      if (!dock) return;
      dock.style.display = this.fabVisible ? "flex" : "none";
      const expanded = this.dockState !== "collapsed";
      dock.dataset.state = this.dockState;
      document.getElementById("rm-dock-controls").hidden = !expanded;
      const fab = document.getElementById("rm-fab");
      const label = !expanded ? "Expand markup tools" : this.active ? "Stop annotating" : "Annotate an element";
      fab.title = label;
      fab.setAttribute("aria-label", label);
      fab.setAttribute("aria-expanded", String(expanded));
      fab.setAttribute("aria-pressed", String(this.active));
      const close = document.getElementById("rm-dock-close");
      close.hidden = !this.fabVisible && !this.active;
      close.style.display = close.hidden ? "none" : "flex";
      close.title = this.active ? "Stop annotating" : "Collapse markup tools";
      close.setAttribute("aria-label", close.title);
    },
    _expandDock() {
      if (!this.active) this.dockState = "expanded";
      this._renderDockState();
    },
    _collapseDock() {
      this._deactivateMode();
      this._closePopup();
      this._closeAllMenus();
      document.getElementById("rm-panel").style.display = "none";
      document.getElementById("rm-panel-toggle").setAttribute("aria-expanded", "false");
      document.getElementById("rm-settings-panel").hidden = true;
      document.getElementById("rm-settings-toggle").setAttribute("aria-expanded", "false");
      this._settingsPanelOpen = false;
      this.dockState = this.fabVisible ? "collapsed" : "expanded";
      this._renderDockState();
      if (this.fabVisible) document.getElementById("rm-fab").focus();
    },
    togglePanel() {
      this._expandDock();
      const panel = document.getElementById("rm-panel");
      const opening = panel.style.display !== "flex" || panel.dataset.view === "settings";
      panel.dataset.view = "feedback";
      panel.querySelector("h3").textContent = "Feedback";
      document.getElementById("rm-settings-panel").hidden = true;
      document.getElementById("rm-settings-toggle").setAttribute("aria-expanded", "false");
      this._settingsPanelOpen = false;
      panel.style.display = opening ? "flex" : "none";
      document.getElementById("rm-panel-toggle").setAttribute("aria-expanded", String(opening));
    },
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
      if (el && !this._isToolbar(el)) {
        this.clickedElement = el;
        // Suppress the press so host controls (buttons, drag handles, form
        // fields) don't act before mouseup/click is blocked. Guard for the
        // synthetic object passed from the touchstart handler.
        if (typeof event.preventDefault === "function") event.preventDefault();
        if (typeof event.stopPropagation === "function") event.stopPropagation();
      }
    },
    async _handleMouseUp(event) {
      if (!this.active) return;
      const el = this.clickedElement || document.elementFromPoint(event.clientX, event.clientY);
      if (!el || this._isToolbar(el)) return;
      event.preventDefault();
      event.stopPropagation();
      const sel = window.getSelection();
      this.selectedText = (sel && sel.toString().trim().length > 0) ? sel.toString().trim() : null;
      this._currentElement = this._identify(el);
      this._currentScreenshot = null;

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
      const openList = this.root?.querySelector(".rm-menu-list.rm-menu-open");
      const openMenu = this._menuForElement(openList);
      if (openMenu) {
        const options = Array.from(openList.querySelectorAll(".rm-menu-option"));
        const focusedIndex = options.indexOf(document.activeElement);

        if (event.key === "Escape") {
          this._closeMenu(openMenu, true);
          event.preventDefault();
          event.stopPropagation();
          return;
        }
        if (event.key === "Tab") {
          this._closeMenu(openMenu);
          return;
        }
        if (event.key === "ArrowDown" || event.key === "ArrowUp") {
          const direction = event.key === "ArrowDown" ? 1 : -1;
          const start = focusedIndex === -1 ? 0 : focusedIndex;
          const next = (start + direction + options.length) % options.length;
          options[next]?.focus();
          event.preventDefault();
          event.stopPropagation();
          return;
        }
        if (event.key === "Home" || event.key === "End") {
          const option = event.key === "Home" ? options[0] : options[options.length - 1];
          option?.focus();
          event.preventDefault();
          event.stopPropagation();
          return;
        }
        if ((event.key === "Enter" || event.key === " ") && focusedIndex !== -1) {
          this._selectMenuOption(options[focusedIndex]);
          event.preventDefault();
          event.stopPropagation();
          return;
        }
      }

      const trigger = event.target.closest?.(".rm-menu-btn");
      if (trigger && this.root?.contains(trigger) &&
          ["Enter", " ", "ArrowDown", "ArrowUp"].includes(event.key)) {
        const menu = this._menuForElement(trigger);
        if (menu) this._openMenu(menu);
        event.preventDefault();
        event.stopPropagation();
        return;
      }

      if (event.key === "Escape") {
        const popup = document.getElementById("rm-popup");
        if (popup && popup.style.display === "block") {
          this._closePopup();
          event.preventDefault();
          event.stopPropagation();
          return;
        }
        if (this.active) {
          this._deactivateMode();
          event.preventDefault();
          event.stopPropagation();
          return;
        }
      }
      if (event.key === "Escape" && this.dockState === "expanded") {
        this._collapseDock();
        event.preventDefault();
        event.stopPropagation();
        return;
      }
      if ((event.metaKey || event.ctrlKey) && event.key === "Enter") {
        const popup = document.getElementById("rm-popup");
        if (popup && popup.style.display === "block") {
          this.submitAnnotation();
        }
      }
    },
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
  });

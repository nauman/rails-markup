  Object.assign(RailsMarkupToolbar, {
    _storageKey() {
      const endpoint = (this.endpoint || "/feedback/api").replace(/\/+$/, "") || "/";
      return `rm-annotations:${encodeURIComponent(endpoint)}`;
    },
    _toolbarSettingsKey() {
      const endpoint = (this.endpoint || "/feedback/api").replace(/\/+$/, "") || "/";
      return `rm-toolbar-settings:${encodeURIComponent(endpoint)}`;
    },
    _pageUrl() { return window.location.pathname + window.location.search; },
    _pageStorageKey() { return this._storageKey() + ":" + this._pageUrl(); },
    _normalizeToolbarSettings(candidate = {}) {
      const source = candidate && typeof candidate === "object" && !Array.isArray(candidate) ? candidate : {};
      const normalized = {};
      if (this._validToolbarAccent(source.accent)) normalized.accent = source.accent;
      if (this._validToolbarPosition(source.position)) normalized.position = source.position;
      if (this._validToolbarSize(source.size)) normalized.size = source.size;
      if (typeof source.fabVisible === "boolean") normalized.fabVisible = source.fabVisible;
      if (typeof source.enableScreenshots === "boolean") normalized.enableScreenshots = source.enableScreenshots;
      return normalized;
    },
    _loadToolbarSettings() {
      try {
        const raw = localStorage.getItem(this._toolbarSettingsKey());
        if (!raw) return {};
        return this._normalizeToolbarSettings(JSON.parse(raw));
      } catch (e) {
        console.warn("[rails-markup] settings load failed:", e);
        return {};
      }
    },
    _saveToolbarSettings(settings = this.toolbarSettings || {}) {
      try {
        localStorage.setItem(this._toolbarSettingsKey(), JSON.stringify(this._normalizeToolbarSettings(settings)));
        return true;
      } catch (e) {
        console.warn("[rails-markup] settings save failed:", e);
        return false;
      }
    },
    _saveToStorage() {
      try {
        // Cross-tab storage-event merging is deferred: safely reconciling ordered
        // upserts and tombstones needs conflict semantics, not a last-write merge.
        localStorage.setItem(this._storageKey(), JSON.stringify({
          annotations: this.annotations,
          nextId: this.nextId,
          outbox: this.outbox,
          legacyMigrations: this.legacyMigrations
        }));
        return true;
      }
      catch (e) {
        console.warn("[rails-markup] save failed:", e);
        return false;
      }
    },
    _persistLocalMutation(type, dirtyFields, mutate) {
      return this._commitLocalStateChange(() => {
        const annotation = mutate();
        this._queueLocalMutation(type, annotation, dirtyFields);
      });
    },
    _queueLocalMutation(type, annotation, dirtyFields) {
      const currentEntry = this.outbox[annotation.clientId];
      const revision = Math.max(annotation.revision || 0, currentEntry?.revision || 0) + 1;
      const baseRevision = Number.isInteger(currentEntry?.baseRevision)
        ? currentEntry.baseRevision
        : (Number.isInteger(annotation.serverRevision) ? annotation.serverRevision : 0);

      if (type === "delete") {
        this.outbox[annotation.clientId] = {
          type: "delete",
          clientId: annotation.clientId,
          revision,
          baseRevision,
          syncState: "pending"
        };
      } else {
        const existingDirtyFields = currentEntry?.type === "upsert" ? currentEntry.dirtyFields : [];
        annotation.dirtyFields = this._mergeDirtyFields(annotation.dirtyFields, existingDirtyFields, dirtyFields);
        annotation.syncState = "pending";
        annotation.revision = revision;
        this.outbox[annotation.clientId] = {
          type: "upsert",
          clientId: annotation.clientId,
          revision,
          baseRevision,
          syncState: "pending",
          annotation: this._desiredState(annotation),
          dirtyFields: annotation.dirtyFields.slice()
        };
      }
    },
    _commitLocalStateChange(mutate) {
      const snapshot = this._localStateSnapshot();
      mutate();
      if (this._saveToStorage()) {
        this._storageError = null;
        this._scheduleOutboxFlush();
        return true;
      }

      this.annotations = snapshot.annotations;
      this.outbox = snapshot.outbox;
      this.nextId = snapshot.nextId;
      this.legacyMigrations = snapshot.legacyMigrations;
      this.toolbarSettings = snapshot.toolbarSettings || {};
      this._storageError = "Changes could not be saved in this browser. Free storage space and try again.";
      this._renderPins();
      this._rebuildList();
      this._updateCount();
      const panel = document.getElementById("rm-panel");
      if (panel) panel.style.display = "flex";
      this._expandDock();
      document.getElementById("rm-panel-toggle")?.setAttribute("aria-expanded", "true");
      return false;
    },
    _localStateSnapshot() {
      return JSON.parse(JSON.stringify({
        annotations: this.annotations,
        outbox: this.outbox,
        nextId: this.nextId,
        legacyMigrations: this.legacyMigrations,
        toolbarSettings: this.toolbarSettings
      }));
    },
    _mergeDirtyFields(...collections) {
      const merged = [];
      collections.flat().forEach(field => {
        const canonical = field === "selectedText" ? "selected_text" : field;
        if (canonical && !merged.includes(canonical)) merged.push(canonical);
      });
      return merged;
    },
    _scheduleOutboxFlush() {
      if (this._outboxFlushScheduled) return;
      this._outboxFlushScheduled = true;
      this._outboxFlushTimer = setTimeout(() => {
        this._outboxFlushScheduled = false;
        this._outboxFlushTimer = null;
        Promise.resolve(this._flushOutbox()).catch(error => console.warn("[rails-markup] outbox flush failed:", error));
      }, 0);
    },
    _flushOutbox() {
      if (this._flushPromise) return this._flushPromise;
      if (this._pullPromise) {
        if (!this._flushAfterPullPromise) {
          this._flushAfterPullPromise = this._pullPromise.then(() => {
            this._flushAfterPullPromise = null;
            return this._flushOutbox();
          });
        }
        return this._flushAfterPullPromise;
      }
      if (!navigator.onLine || !this.serverOnline) return Promise.resolve();
      if (this._syncRetryTimer) return Promise.resolve();

      this._flushPromise = this._runOutboxFlush().finally(() => {
        this._flushPromise = null;
      });
      return this._flushPromise;
    },
    async _runOutboxFlush() {
      const clientIds = Object.keys(this.outbox);
      for (const clientId of clientIds) {
        const current = this.outbox[clientId];
        if (!current || current.syncState === "failed") continue;

        const snapshot = this._immutableCopy(current);
        let result;
        try {
          result = await this._sendOutboxEntry(snapshot);
        } catch (error) {
          result = { kind: "retryable", error };
        }

        if (result.kind === "success") {
          if (!this._outboxEntryMatches(snapshot)) {
            const supersedingDelete = this._advanceSupersedingDeleteBaseRevision(snapshot, result.data);
            if (supersedingDelete === "failed") break;
            clientIds.push(clientId);
            continue;
          }
          this._handleSyncSuccess(snapshot, result.data);
          this._resetSyncRetry();
          continue;
        }
        if (result.kind === "auth") {
          this._setSyncUnavailable(result.message || "Authentication required");
          break;
        }
        if (result.kind === "terminal") {
          if (!this._outboxEntryMatches(snapshot)) {
            clientIds.push(clientId);
            continue;
          }
          this._markSyncFailed(snapshot);
          continue;
        }
        if (result.kind === "conflict") {
          const resolution = this._reconcileSyncConflict(snapshot, result);
          await this._pullAnnotations();
          if (resolution === "retry" && this.outbox[clientId]) {
            clientIds.push(clientId);
            continue;
          }
          this._resetSyncRetry();
          continue;
        }
        if (result.kind === "malformed") {
          if (!this._outboxEntryMatches(snapshot)) {
            clientIds.push(clientId);
            continue;
          }
          if (this._recordMalformedResponse(snapshot)) continue;
          break;
        }

        this.serverOnline = false;
        this._updateStatus();
        this._scheduleSyncRetry(result.retryAfter);
        break;
      }
    },
    _advanceSupersedingDeleteBaseRevision(snapshot, server) {
      const current = this.outbox[snapshot.clientId];
      const supersedesUpsert = snapshot.type === "upsert"
        && current?.type === "delete"
        && current.clientId === snapshot.clientId
        && Number.isInteger(current.revision)
        && current.revision > snapshot.revision
        && Number.isInteger(server?.revision);
      if (!supersedesUpsert) return "not-applicable";

      const tombstone = this._immutableCopy(current);
      const committed = this._commitLocalStateChange(() => {
        if (!this._outboxEntryMatches(tombstone)) return;
        const baseRevision = Number.isInteger(tombstone.baseRevision) ? tombstone.baseRevision : 0;
        this.outbox[snapshot.clientId].baseRevision = Math.max(baseRevision, server.revision);
      });
      return committed ? "advanced" : "failed";
    },
    async _sendOutboxEntry(snapshot) {
      const request = this._sameOriginMutationRequest(`/annotations/${encodeURIComponent(snapshot.clientId)}`);
      if (!request) return { kind: "auth", message: "Sync unavailable: endpoint must be same-origin" };

      const options = {
        method: snapshot.type === "delete" ? "DELETE" : "PUT",
        headers: request.headers,
        credentials: "same-origin",
        redirect: "manual",
        signal: AbortSignal.timeout(5000)
      };
      if (snapshot.type === "delete") {
        options.body = JSON.stringify({
          baseRevision: Number.isInteger(snapshot.baseRevision) ? snapshot.baseRevision : 0
        });
      } else {
        options.body = JSON.stringify(Object.assign({}, snapshot.annotation, {
          dirtyFields: snapshot.dirtyFields || [],
          baseRevision: Number.isInteger(snapshot.baseRevision) ? snapshot.baseRevision : 0
        }));
      }

      const response = await fetch(request.url, options);
      return this._classifySyncResponse(snapshot, response);
    },
    _sameOriginMutationRequest(path) {
      const url = this._sameOriginEndpointUrl(path);
      if (!url) return null;
      const headers = { "Content-Type": "application/json", "Accept": "application/json" };
      const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content;
      if (csrfToken) headers["X-CSRF-Token"] = csrfToken;
      return { url, headers };
    },
    _sameOriginEndpointUrl(path) {
      try {
        const rawUrl = `${this.endpoint.replace(/\/$/, "")}/${String(path).replace(/^\//, "")}`;
        const resolved = new URL(rawUrl, window.location.href);
        if (resolved.origin !== window.location.origin) return null;
        return this.endpoint.startsWith("/") && !this.endpoint.startsWith("//")
          ? resolved.pathname + resolved.search
          : resolved.href;
      } catch {
        return null;
      }
    },
    async _classifySyncResponse(snapshot, response) {
      const status = response.status;
      if (status >= 300 && status < 400) return { kind: "auth", message: "Authentication required" };
      if (status === 401 || status === 403 || response.type === "opaqueredirect") {
        return { kind: "auth", message: "Authentication required" };
      }
      if ([408, 425, 429].includes(status) || status >= 500) {
        return { kind: "retryable", retryAfter: this._retryAfterDelay(response) };
      }
      if (status === 409) return this._classifyConflictResponse(snapshot, response);
      if (status >= 400) return { kind: "terminal" };
      if (!response.ok) return { kind: "retryable" };
      if (snapshot.type === "delete") return { kind: "success", data: null };

      const contentType = response.headers.get("Content-Type") || "";
      if (!contentType.toLowerCase().includes("application/json")) {
        return { kind: "auth", message: "Sync unavailable: expected JSON" };
      }

      try {
        const data = await response.json();
        if (!this._validServerAnnotation(data, snapshot.clientId)) return { kind: "malformed" };
        return { kind: "success", data };
      } catch {
        return { kind: "malformed" };
      }
    },
    async _classifyConflictResponse(snapshot, response) {
      const contentType = response.headers.get("Content-Type") || "";
      if (!contentType.toLowerCase().includes("application/json")) return { kind: "malformed" };

      try {
        const body = await response.json();
        if (!this._plainObject(body) || !Object.prototype.hasOwnProperty.call(body, "annotation")) {
          return { kind: "malformed" };
        }
        if (body.annotation === null && snapshot.type === "upsert") {
          return { kind: "conflict", missing: true, data: null };
        }
        if (!this._validServerAnnotation(body.annotation, snapshot.clientId)) return { kind: "malformed" };
        return { kind: "conflict", missing: false, data: body.annotation };
      } catch {
        return { kind: "malformed" };
      }
    },
    _validServerAnnotation(data, expectedClientId) {
      if (!this._plainObject(data)) return false;
      const required = [
        "id", "clientId", "userId", "authorName", "content", "intent", "severity",
        "status", "selectedText", "pageUrl", "target", "metadata", "thread",
        "createdAt", "updatedAt", "revision"
      ];
      if (!required.every(key => Object.prototype.hasOwnProperty.call(data, key))) return false;
      if (typeof data.id !== "string" || data.id.length === 0) return false;
      if (data.clientId !== expectedClientId) return false;
      if (!(data.userId === null || Number.isInteger(data.userId))) return false;
      if (!(data.authorName === null || typeof data.authorName === "string")) return false;
      if (typeof data.content !== "string") return false;
      if (!["fix", "change", "question", "approve"].includes(data.intent)) return false;
      if (!["suggestion", "important", "blocking"].includes(data.severity)) return false;
      if (!["pending", "acknowledged", "resolved", "dismissed"].includes(data.status)) return false;
      if (!(data.selectedText === null || typeof data.selectedText === "string")) return false;
      if (typeof data.pageUrl !== "string" || data.pageUrl.length === 0) return false;
      if (!this._plainObject(data.target) || !this._plainObject(data.metadata)) return false;
      if (!Array.isArray(data.thread)) return false;
      if (!this._validServerTimestamp(data.createdAt) || !this._validServerTimestamp(data.updatedAt)) return false;
      if (!Number.isInteger(data.revision) || data.revision < 0) return false;
      return true;
    },
    _plainObject(value) {
      return Boolean(value) && typeof value === "object" && !Array.isArray(value);
    },
    _validServerTimestamp(value) {
      return typeof value === "string" && value.length > 0 && Number.isFinite(Date.parse(value));
    },
    _handleSyncSuccess(snapshot, data) {
      if (!this._outboxEntryMatches(snapshot)) return;
      this._commitLocalStateChange(() => {
        if (!this._outboxEntryMatches(snapshot)) return;
        if (snapshot.type === "upsert") {
          const annotation = this.annotations.find(candidate => candidate.clientId === snapshot.clientId);
          if (annotation) this._mergeSuccessfulUpsert(annotation, data, snapshot.dirtyFields || []);
        }
        delete this.outbox[snapshot.clientId];
      });
      this._renderPins();
      this._rebuildList();
      this._updateCount();
    },
    _mergeSuccessfulUpsert(annotation, server, sentDirtyFields) {
      if (this._serverRepresentationIsStale(annotation, server)) {
        annotation.dirtyFields = (annotation.dirtyFields || []).filter(field => !sentDirtyFields.includes(field));
        annotation.syncState = "synced";
        return;
      }
      annotation.serverId = server.id;
      annotation.serverRevision = server.revision;
      annotation.userId = server.userId;
      annotation.authorName = server.authorName;
      annotation.createdAt = server.createdAt;
      annotation.serverUpdatedAt = server.updatedAt || annotation.serverUpdatedAt;
      annotation.comment = server.content;
      annotation.intent = server.intent;
      annotation.severity = server.severity;
      annotation.status = server.status;
      annotation.selectedText = server.selectedText;
      annotation.element = server.target || {};
      annotation.metadata = server.metadata || {};
      annotation.thread = server.thread || [];
      annotation.pageUrl = server.pageUrl || annotation.pageUrl;
      annotation.pathname = server.pageUrl || annotation.pathname;
      annotation.dirtyFields = (annotation.dirtyFields || []).filter(field => !sentDirtyFields.includes(field));
      annotation.syncState = "synced";
    },
    _reconcileSyncConflict(snapshot, conflict) {
      if (!this._outboxEntryMatches(snapshot)) return "stop";

      let resolution = "stop";
      const committed = this._commitLocalStateChange(() => {
        if (!this._outboxEntryMatches(snapshot)) return;
        const entry = this.outbox[snapshot.clientId];
        const annotation = this.annotations.find(candidate => candidate.clientId === snapshot.clientId);

        if (snapshot.type === "delete") {
          delete this.outbox[snapshot.clientId];
          if (annotation) this._mergePulledAnnotation(annotation, conflict.data, null);
          else this.annotations.push(this._annotationFromServer(conflict.data));
          this._assignDisplayIds();
          return;
        }

        if (conflict.missing) {
          if (entry.missingConflictRebased) {
            entry.syncState = "failed";
            if (annotation) annotation.syncState = "failed";
            return;
          }
          if (!annotation) {
            entry.syncState = "failed";
            return;
          }
          // Recreate once from the complete desired browser state. Replaying a
          // narrow edit delta onto a new row can omit required fields and lose
          // the user's annotation to a permanent validation failure.
          annotation.dirtyFields = this._legacyDirtyFields(annotation);
          entry.annotation = this._desiredState(annotation);
          entry.dirtyFields = annotation.dirtyFields.slice();
          entry.baseRevision = 0;
          entry.missingConflictRebased = true;
          annotation.serverId = null;
          annotation.serverRevision = 0;
          resolution = "retry";
          return;
        }

        if (!annotation) {
          entry.syncState = "failed";
          return;
        }
        this._mergePulledAnnotation(annotation, conflict.data, entry);
        entry.annotation = this._desiredState(annotation);
        entry.dirtyFields = (annotation.dirtyFields || []).slice();
        entry.baseRevision = conflict.data.revision;
        delete entry.missingConflictRebased;
        resolution = "retry";
      });
      if (!committed) return "stop";
      this._renderPins();
      this._rebuildList();
      this._updateCount();
      return resolution;
    },
    _markSyncFailed(snapshot) {
      if (!this._outboxEntryMatches(snapshot)) return;
      this._commitLocalStateChange(() => {
        const entry = this.outbox[snapshot.clientId];
        if (!entry || !this._outboxEntryMatches(snapshot)) return;
        entry.syncState = "failed";
        const annotation = this.annotations.find(candidate => candidate.clientId === snapshot.clientId);
        if (annotation) annotation.syncState = "failed";
      });
      this._rebuildList();
    },
    _recordMalformedResponse(snapshot) {
      if (!this._outboxEntryMatches(snapshot)) return true;
      const attempts = (this.outbox[snapshot.clientId].malformedAttempts || 0) + 1;
      if (attempts >= this._syncMalformedLimit) {
        this._markSyncFailed(snapshot);
        return true;
      }
      this._commitLocalStateChange(() => {
        if (this._outboxEntryMatches(snapshot)) this.outbox[snapshot.clientId].malformedAttempts = attempts;
      });
      this._scheduleSyncRetry();
      return false;
    },
    _outboxEntryMatches(snapshot) {
      const current = this.outbox[snapshot.clientId];
      return Boolean(current) && JSON.stringify(current) === JSON.stringify(snapshot);
    },
    _immutableCopy(value) {
      return JSON.parse(JSON.stringify(value));
    },
    _retryAfterDelay(response) {
      const value = response.headers.get("Retry-After");
      if (!value) return null;
      const seconds = Number(value);
      const delay = Number.isFinite(seconds) ? seconds * 1000 : Date.parse(value) - Date.now();
      if (!Number.isFinite(delay)) return null;
      return Math.min(this._syncMaxRetryDelay, Math.max(0, delay));
    },
    _scheduleSyncRetry(requestedDelay) {
      if (this._syncRetryTimer) return;
      this._syncRetryAttempt += 1;
      const exponential = this._syncBaseRetryDelay * (2 ** (this._syncRetryAttempt - 1));
      this._syncRetryDelay = Math.min(this._syncMaxRetryDelay, requestedDelay ?? exponential);
      this._syncRetryTimer = setTimeout(async () => {
        this._syncRetryTimer = null;
        await this._checkHealth();
      }, this._syncRetryDelay);
    },
    _resetSyncRetry() {
      this._syncRetryAttempt = 0;
      this._syncRetryDelay = 0;
      if (this._syncRetryTimer) clearTimeout(this._syncRetryTimer);
      this._syncRetryTimer = null;
      this._syncUnavailable = null;
    },
    _setSyncUnavailable(message) {
      this.serverOnline = false;
      this._syncUnavailable = message;
      this._updateStatus();
    },
    _retrySync(clientId) {
      const entry = this.outbox[clientId];
      if (!entry || entry.syncState !== "failed") return;
      const committed = this._commitLocalStateChange(() => {
        entry.syncState = "pending";
        const annotation = this.annotations.find(candidate => candidate.clientId === clientId);
        if (annotation) annotation.syncState = "pending";
      });
      if (!committed) return;
      this._rebuildList();
    },
    _loadFromStorage() {
      try {
        let raw = localStorage.getItem(this._storageKey());
        if (raw) {
          const data = JSON.parse(raw);
          const validDocument = data && typeof data === "object" && !Array.isArray(data);
          this.annotations = validDocument && Array.isArray(data.annotations) ? data.annotations : [];
          this.nextId = validDocument && Number.isInteger(data.nextId) && data.nextId > 0 ? data.nextId : (this.annotations.length + 1);
          this.outbox = validDocument && data.outbox && typeof data.outbox === "object" && !Array.isArray(data.outbox) ? data.outbox : {};
          this.legacyMigrations = validDocument && data.legacyMigrations && typeof data.legacyMigrations === "object" && !Array.isArray(data.legacyMigrations)
            ? data.legacyMigrations
            : {};
        }
        // Pre-1.3 bare storage has no endpoint provenance, so it is left intact
        // unless the host explicitly designates this endpoint. Page-qualified
        // legacy keys are only claimed by a toolbar currently on that exact page.
        const migratedKeys = this._migrateUnnamespacedStorage();
        migratedKeys.push(...this._migratePageAnnotations());
        this._normalizeStoredState();
        this._recordLegacyMigrations();
        if (this._saveToStorage()) this._cleanupMigratedKeys(migratedKeys);
        this._rebuildList();
        this._updateCount();
      } catch (e) { console.warn("[rails-markup] load failed:", e); }
    },
    _migrateUnnamespacedStorage() {
      const sourceKeys = [];
      const designatedEndpoint = (this.legacyStorageEndpoint || "").replace(/\/+$/, "");
      const currentEndpoint = (this.endpoint || "").replace(/\/+$/, "");
      const claimBareStorage = Boolean(designatedEndpoint) && designatedEndpoint === currentEndpoint;
      const currentPageKey = `rm-annotations:${this._pageUrl()}`;
      for (let index = 0; index < localStorage.length; index++) {
        const key = localStorage.key(index);
        if ((claimBareStorage && key === "rm-annotations") || key === currentPageKey) sourceKeys.push(key);
      }

      const migratedKeys = [];
      const legacyAnnotations = [];
      const legacyOutbox = {};
      const consolidatedClientIds = new Set(
        this.annotations.map(annotation => annotation.clientId).filter(clientId => this._validClientId(clientId))
      );
      sourceKeys.forEach(key => {
        try {
          const data = JSON.parse(localStorage.getItem(key));
          if (!this._plainObject(data)) return;
          const hasAnnotations = Array.isArray(data.annotations);
          const hasOutbox = key === "rm-annotations" && this._plainObject(data.outbox);
          if (!hasAnnotations && !hasOutbox) return;

          if (hasAnnotations) {
            data.annotations.forEach((annotation, index) => {
              if (!this._plainObject(annotation)) return;
              const fingerprint = this._legacyMigrationFingerprint(key, index, annotation);
              const migratedClientId = this.legacyMigrations[fingerprint];
              if (this._validClientId(migratedClientId) && consolidatedClientIds.has(migratedClientId)) return;
              if (this._validClientId(migratedClientId)) annotation.clientId = migratedClientId;
              if (this._validClientId(annotation.clientId) && consolidatedClientIds.has(annotation.clientId)) return;
              Object.defineProperty(annotation, "_legacyMigrationFingerprint", {
                configurable: true,
                value: fingerprint
              });
              legacyAnnotations.push(annotation);
              if (this._validClientId(annotation.clientId)) consolidatedClientIds.add(annotation.clientId);
            });
          }
          if (hasOutbox) Object.assign(legacyOutbox, data.outbox);
          if (Number.isInteger(data.nextId) && data.nextId > this.nextId) this.nextId = data.nextId;
          migratedKeys.push(key);
        } catch {}
      });

      this.annotations = legacyAnnotations.concat(this.annotations);
      this.outbox = Object.assign({}, legacyOutbox, this.outbox);
      return migratedKeys;
    },
    _migratePageAnnotations() {
      // Find and merge per-page annotation keys only within this endpoint namespace.
      const prefix = this._storageKey() + ":";
      const migratedKeys = [];
      const seenIds = new Set(this.annotations.map(a => a.id));
      const consolidatedClientIds = new Set(this.annotations.map(a => a.clientId).filter(clientId => this._validClientId(clientId)));
      for (let i = 0; i < localStorage.length; i++) {
        const key = localStorage.key(i);
        if (key && key.startsWith(prefix)) {
          try {
            const data = JSON.parse(localStorage.getItem(key));
            if (data && Array.isArray(data.annotations)) {
              data.annotations.forEach((a, index) => {
                const fingerprint = this._legacyMigrationFingerprint(key, index, a);
                const migratedClientId = this.legacyMigrations[fingerprint];
                if (this._validClientId(migratedClientId) && consolidatedClientIds.has(migratedClientId)) return;
                if (this._validClientId(migratedClientId)) a.clientId = migratedClientId;
                Object.defineProperty(a, "_legacyMigrationFingerprint", { configurable: true, value: fingerprint });
                // Legacy ids were per-page counters, so different pages can reuse
                // the same id. Reassign a fresh id on collision instead of
                // dropping the annotation (which silently lost data).
                if (seenIds.has(a.id)) a.id = this.nextId++;
                seenIds.add(a.id);
                this.annotations.push(a);
                if (a.id >= this.nextId) this.nextId = a.id + 1;
              });
              migratedKeys.push(key);
            }
          } catch {}
        }
      }
      return migratedKeys;
    },
    _legacyMigrationFingerprint(key, index, annotation) {
      const input = `${key}\u0000${index}\u0000${JSON.stringify(annotation)}`;
      let hash = 2166136261;
      for (let i = 0; i < input.length; i++) hash = Math.imul(hash ^ input.charCodeAt(i), 16777619);
      return `${key}:${index}:${(hash >>> 0).toString(16)}`;
    },
    _recordLegacyMigrations() {
      this.annotations.forEach(annotation => {
        if (!annotation._legacyMigrationFingerprint) return;
        this.legacyMigrations[annotation._legacyMigrationFingerprint] = annotation.clientId;
        delete annotation._legacyMigrationFingerprint;
      });
    },
    _cleanupMigratedKeys(keys) {
      keys.forEach(key => {
        try { localStorage.removeItem(key); }
        catch (e) { console.warn("[rails-markup] legacy cleanup failed:", e); }
      });
    },
    _normalizeStoredState() {
      if (!this.outbox || typeof this.outbox !== "object" || Array.isArray(this.outbox)) this.outbox = {};

      const usedClientIds = new Set(this.annotations.map(annotation => annotation.clientId).filter(clientId => this._validClientId(clientId)));
      const invalidOutboxOwners = this._invalidOutboxOwners();
      const normalized = this.annotations.map((annotation, index) => {
        const originalClientId = annotation.clientId;
        if (!this._validClientId(originalClientId)) {
          let replacementClientId;
          do { replacementClientId = this._newClientId(); } while (usedClientIds.has(replacementClientId));
          usedClientIds.add(replacementClientId);
          annotation.clientId = replacementClientId;
          if (invalidOutboxOwners.get(originalClientId) === annotation) this._rekeyOutbox(originalClientId, replacementClientId);
        }
        if (annotation.serverId == null) annotation.serverId = annotation.server_id ?? null;
        if (annotation.serverUpdatedAt == null) annotation.serverUpdatedAt = annotation.server_updated_at ?? null;
        if (!Number.isInteger(annotation.serverRevision) || annotation.serverRevision < 0) {
          annotation.serverRevision = Number.isInteger(annotation.server_revision) && annotation.server_revision >= 0
            ? annotation.server_revision
            : 0;
        }
        if (!Array.isArray(annotation.dirtyFields)) annotation.dirtyFields = [];
        annotation.pageUrl = annotation.pageUrl || annotation.pathname || this._pageUrl();
        annotation.pathname = annotation.pageUrl;

        return { annotation, index };
      });

      this._normalizeOutboxEnvelopes();

      const byClientId = new Map();
      normalized.forEach(candidate => {
        const current = byClientId.get(candidate.annotation.clientId);
        if (!current || this._isNewerLocalRecord(candidate, current)) byClientId.set(candidate.annotation.clientId, candidate);
      });
      this.annotations = Array.from(byClientId.values())
        .sort((left, right) => left.index - right.index)
        .map(candidate => candidate.annotation);

      this._assignDisplayIds();
      this.annotations.forEach(annotation => {
        const mapped = annotation.serverId != null;
        const queuedEntry = this.outbox[annotation.clientId];
        const queued = Boolean(queuedEntry);
        const annotationRevision = Number.isInteger(annotation.revision) && annotation.revision >= 0 ? annotation.revision : 0;
        annotation.revision = annotationRevision;
        annotation.syncState = (queued && annotation.syncState === "failed")
          ? "failed"
          : ((queued || !mapped) ? "pending" : "synced");
        if (!this.outbox[annotation.clientId] && !mapped) {
          annotation.dirtyFields = this._legacyDirtyFields(annotation);
          this.outbox[annotation.clientId] = {
            type: "upsert",
            clientId: annotation.clientId,
            revision: annotation.revision,
            baseRevision: annotation.serverRevision,
            syncState: "pending",
            annotation: this._desiredState(annotation),
            dirtyFields: annotation.dirtyFields.slice()
          };
        }
      });
    },
    _normalizeOutboxEnvelopes() {
      const normalized = {};

      Object.entries(this.outbox).forEach(([storedClientId, candidate]) => {
        if (!this._plainObject(candidate)) return;

        const nestedClientId = candidate.annotation?.clientId;
        const clientId = this._validClientId(nestedClientId)
          ? nestedClientId
          : (this._validClientId(candidate.clientId)
            ? candidate.clientId
            : (this._validClientId(storedClientId) ? storedClientId : null));
        if (!clientId) return;

        const type = candidate.type === "delete"
          ? "delete"
          : ((candidate.type === "upsert" || this._plainObject(candidate.annotation)) ? "upsert" : null);
        if (!type) return;

        const annotation = this.annotations.find(record => record.clientId === clientId);
        const candidateRevision = Number.isInteger(candidate.revision) && candidate.revision >= 0 ? candidate.revision : 0;
        const annotationRevision = Number.isInteger(annotation?.revision) && annotation.revision >= 0 ? annotation.revision : 0;
        const candidateBaseRevision = Number.isInteger(candidate.baseRevision) && candidate.baseRevision >= 0
          ? candidate.baseRevision
          : 0;
        const annotationBaseRevision = Number.isInteger(annotation?.serverRevision) && annotation.serverRevision >= 0
          ? annotation.serverRevision
          : 0;
        const envelope = Object.assign({}, candidate, {
          type,
          clientId,
          revision: Math.max(candidateRevision, annotationRevision),
          baseRevision: Math.max(candidateBaseRevision, annotationBaseRevision),
          syncState: candidate.syncState === "failed" ? "failed" : "pending"
        });

        if (type === "upsert") {
          envelope.annotation = Object.assign({}, candidate.annotation, { clientId });
          envelope.dirtyFields = this._mergeDirtyFields(candidate.dirtyFields || envelope.annotation.dirtyFields || []);
        }
        normalized[clientId] = envelope;
      });

      this.outbox = normalized;
    },
    _isNewerLocalRecord(candidate, current) {
      const timestamp = value => {
        const parsed = Date.parse(value || "");
        return Number.isNaN(parsed) ? -Infinity : parsed;
      };
      const candidateUpdatedAt = timestamp(candidate.annotation.updatedAt || candidate.annotation.updated_at);
      const currentUpdatedAt = timestamp(current.annotation.updatedAt || current.annotation.updated_at);
      if (candidateUpdatedAt !== currentUpdatedAt) return candidateUpdatedAt > currentUpdatedAt;
      return candidate.index > current.index;
    },
    _assignDisplayIds() {
      const validIds = this.annotations
        .map(annotation => annotation.id)
        .filter(id => Number.isInteger(id) && id > 0);
      let candidateId = Math.max(1, Number.isInteger(this.nextId) ? this.nextId : 1, ...validIds.map(id => id + 1));
      const usedIds = new Set();

      this.annotations.forEach(annotation => {
        if (!Number.isInteger(annotation.id) || annotation.id <= 0 || usedIds.has(annotation.id)) {
          while (usedIds.has(candidateId)) candidateId += 1;
          annotation.id = candidateId++;
        }
        usedIds.add(annotation.id);
      });

      this.nextId = Math.max(candidateId, ...Array.from(usedIds, id => id + 1), 1);
    },
    _legacyDirtyFields(annotation) {
      const fields = this._browserCreateFields();
      if (annotation.status && annotation.status !== "pending") fields.push("status");
      return fields;
    },
    _browserCreateFields() {
      return ["content", "intent", "severity", "selected_text", "target", "page_url", "metadata"];
    },
    _desiredState(annotation) {
      const sourceMetadata = annotation.metadata && typeof annotation.metadata === "object" ? annotation.metadata : {};
      const metadata = {};
      ["tool", "url", "localId", "sessionId", "screenshot"].forEach(key => {
        if (sourceMetadata[key] != null) metadata[key] = sourceMetadata[key];
      });
      if (metadata.tool == null) metadata.tool = "rails-markup";
      if (metadata.url == null && annotation.url) metadata.url = annotation.url;
      if (metadata.localId == null && annotation.id != null) metadata.localId = annotation.id;
      if (metadata.sessionId == null && this.sessionId != null) metadata.sessionId = this.sessionId;
      if (metadata.screenshot == null && annotation.screenshot) metadata.screenshot = annotation.screenshot;

      return JSON.parse(JSON.stringify({
        clientId: annotation.clientId,
        page_url: annotation.pageUrl || annotation.pathname || this._pageUrl(),
        content: annotation.comment ?? annotation.content ?? "",
        intent: annotation.intent,
        severity: annotation.severity,
        selected_text: annotation.selectedText ?? annotation.selected_text ?? null,
        target: annotation.element || annotation.target || {},
        metadata,
        status: annotation.status || "pending"
      }));
    },
    _validClientId(clientId) {
      return typeof clientId === "string" && /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(clientId);
    },
    _invalidOutboxOwners() {
      const owners = new Map();
      this.annotations.forEach(annotation => {
        const clientId = annotation.clientId;
        if (!clientId || this._validClientId(clientId) || owners.has(clientId) || !this.outbox[clientId]) return;

        const peers = this.annotations.filter(candidate => candidate.clientId === clientId);
        const desired = this.outbox[clientId].annotation || this.outbox[clientId];
        const desiredId = desired.id ?? desired.metadata?.localId;
        const desiredComment = desired.comment ?? desired.content;
        const owner = peers.find(candidate => desiredId != null && candidate.id === desiredId)
          || peers.find(candidate => desiredComment != null && (candidate.comment ?? candidate.content) === desiredComment)
          || peers[0];
        owners.set(clientId, owner);
      });
      return owners;
    },
    _rekeyOutbox(oldClientId, newClientId) {
      if (!oldClientId || !this.outbox[oldClientId]) return;
      const entry = this.outbox[oldClientId];
      delete this.outbox[oldClientId];
      if (entry.annotation) entry.annotation.clientId = newClientId;
      if (entry.clientId) entry.clientId = newClientId;
      this.outbox[newClientId] = entry;
    },
    _newClientId() {
      if (global.crypto && typeof global.crypto.randomUUID === "function") return global.crypto.randomUUID();
      const bytes = new Uint8Array(16);
      if (global.crypto && typeof global.crypto.getRandomValues === "function") global.crypto.getRandomValues(bytes);
      else bytes.forEach((_, index) => { bytes[index] = Math.floor(Math.random() * 256); });
      bytes[6] = (bytes[6] & 0x0f) | 0x40;
      bytes[8] = (bytes[8] & 0x3f) | 0x80;
      const hex = Array.from(bytes, byte => byte.toString(16).padStart(2, "0")).join("");
      return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
    },
    _pullAnnotations() {
      const pageUrl = this._pageUrl();
      if (this._pullPromise && this._pullPageUrl === pageUrl) return this._pullPromise;

      const previousPull = this._pullPromise;
      const operation = previousPull
        ? previousPull.then(() => this._performAnnotationPull(pageUrl))
        : this._performAnnotationPull(pageUrl);
      let trackedPull;
      trackedPull = operation.finally(() => {
        if (this._pullPromise !== trackedPull) return;
        this._pullPromise = null;
        this._pullPageUrl = null;
      });
      this._pullPageUrl = pageUrl;
      this._pullPromise = trackedPull;
      return trackedPull;
    },
    _performAnnotationPull(pageUrl) {
      return this._runAnnotationPull(pageUrl)
        .then(complete => {
          this._pullNeeded = !complete;
          return complete;
        })
        .catch(() => {
          this._pullNeeded = true;
          return false;
        });
    },
    async _runAnnotationPull(pageUrl) {
      const url = this._sameOriginEndpointUrl(`/annotations?page_url=${encodeURIComponent(pageUrl)}`);
      if (!url) {
        this._setSyncUnavailable("Sync unavailable: endpoint must be same-origin");
        return false;
      }

      const response = await fetch(url, {
        method: "GET",
        headers: { "Accept": "application/json" },
        credentials: "same-origin",
        redirect: "manual",
        signal: AbortSignal.timeout(5000)
      });
      if (!response.ok || response.status >= 300 || response.type === "opaqueredirect") return false;
      const contentType = response.headers.get("Content-Type") || "";
      if (!contentType.toLowerCase().includes("application/json")) return false;

      let records;
      try { records = await response.json(); }
      catch { return false; }
      if (pageUrl !== this._pageUrl() || !this._validPullRecords(records, pageUrl)) return false;
      return this._reconcilePull(pageUrl, records);
    },
    _validPullRecords(records, pageUrl) {
      if (!Array.isArray(records)) return false;
      const clientIds = new Set();
      return records.every(record => {
        const clientId = record?.clientId;
        if (!this._validClientId(clientId) || clientIds.has(clientId)) return false;
        clientIds.add(clientId);
        return record.pageUrl === pageUrl && this._validServerAnnotation(record, clientId);
      });
    },
    _reconcilePull(pageUrl, records) {
      const committed = this._commitLocalStateChange(() => {
        const presentClientIds = new Set(records.map(record => record.clientId));
        records.forEach(server => {
          const outboxEntry = this.outbox[server.clientId];
          if (outboxEntry?.type === "delete") return;

          const annotation = this.annotations.find(candidate => candidate.clientId === server.clientId);
          if (annotation) this._mergePulledAnnotation(annotation, server, outboxEntry);
          else this.annotations.push(this._annotationFromServer(server));
        });

        this.annotations = this.annotations.filter(annotation => {
          const annotationPage = annotation.pageUrl || annotation.pathname;
          if (annotationPage !== pageUrl || presentClientIds.has(annotation.clientId)) return true;
          return Boolean(this.outbox[annotation.clientId]) || annotation.syncState !== "synced";
        });

        this._assignDisplayIds();
        Object.entries(this.outbox).forEach(([clientId, entry]) => {
          if (entry?.type !== "upsert") return;
          const annotation = this.annotations.find(candidate => candidate.clientId === clientId);
          if (!annotation) return;
          entry.annotation = this._desiredState(annotation);
          entry.dirtyFields = (annotation.dirtyFields || []).slice();
          entry.baseRevision = Number.isInteger(annotation.serverRevision) ? annotation.serverRevision : 0;
        });
      });
      if (!committed) return false;
      this._renderPins();
      this._rebuildList();
      this._updateCount();
      return true;
    },
    _mergePulledAnnotation(annotation, server, outboxEntry) {
      if (this._serverRepresentationIsStale(annotation, server)) return;
      const dirtyFields = new Set(this._mergeDirtyFields(annotation.dirtyFields || [], outboxEntry?.dirtyFields || []));
      const browserFields = [
        ["content", "comment"],
        ["intent", "intent"],
        ["severity", "severity"],
        ["selected_text", "selectedText"],
        ["target", "element"],
        ["metadata", "metadata"],
        ["status", "status"]
      ];
      browserFields.forEach(([dirtyField, localField]) => {
        if (dirtyFields.has(dirtyField)) return;
        const serverField = {
          content: "content", selected_text: "selectedText", target: "target"
        }[dirtyField] || dirtyField;
        annotation[localField] = this._immutableCopy(server[serverField]);
      });
      if (!dirtyFields.has("page_url")) {
        annotation.pageUrl = server.pageUrl;
        annotation.pathname = server.pageUrl;
      }
      annotation.serverId = server.id;
      annotation.serverRevision = server.revision;
      annotation.userId = server.userId;
      annotation.authorName = server.authorName;
      annotation.createdAt = server.createdAt;
      annotation.serverUpdatedAt = server.updatedAt;
      annotation.thread = this._immutableCopy(server.thread);
      annotation.dirtyFields = Array.from(dirtyFields);
      annotation.syncState = outboxEntry ? (outboxEntry.syncState || "pending") : "synced";
      if (!dirtyFields.has("metadata") && server.metadata?.url) annotation.url = server.metadata.url;
    },
    _annotationFromServer(server) {
      return {
        id: null,
        clientId: server.clientId,
        serverId: server.id,
        serverRevision: server.revision,
        userId: server.userId,
        authorName: server.authorName,
        syncState: "synced",
        serverUpdatedAt: server.updatedAt,
        dirtyFields: [],
        revision: 0,
        comment: server.content,
        intent: server.intent,
        severity: server.severity,
        status: server.status,
        selectedText: server.selectedText,
        element: this._immutableCopy(server.target),
        metadata: this._immutableCopy(server.metadata),
        pathname: server.pageUrl,
        pageUrl: server.pageUrl,
        url: server.metadata?.url || server.pageUrl,
        thread: this._immutableCopy(server.thread),
        createdAt: server.createdAt
      };
    },
    _serverRepresentationIsStale(annotation, server) {
      if (Number.isInteger(annotation.serverRevision) && Number.isInteger(server.revision)) {
        return server.revision < annotation.serverRevision;
      }
      const localTimestamp = Date.parse(annotation.serverUpdatedAt || "");
      const serverTimestamp = Date.parse(server.updatedAt || "");
      return Number.isFinite(localTimestamp) && Number.isFinite(serverTimestamp) && serverTimestamp < localTimestamp;
    },
    _onVisibilityChange() {
      if (document.hidden) {
        // Tab hidden — pause health checks to save resources
        if (this.healthInterval) { clearInterval(this.healthInterval); this.healthInterval = null; }
      } else {
        // Tab visible — resume health checks immediately
        if (!this.healthInterval) {
          this._checkHealth();
          this.healthInterval = setInterval(() => this._checkHealth(), this.healthIntervalMs);
        }
      }
    },
    _onOnline() {
      return this._checkHealth();
    },
    _checkHealth() {
      if (this._healthPromise) return this._healthPromise;
      this._healthPromise = this._runHealthCheck().finally(() => { this._healthPromise = null; });
      return this._healthPromise;
    },
    async _runHealthCheck() {
      try {
        const healthUrl = this._sameOriginEndpointUrl("/health");
        if (!healthUrl) {
          this._setSyncUnavailable("Sync unavailable: endpoint must be same-origin");
          return;
        }
        const resp = await fetch(healthUrl, { signal: AbortSignal.timeout(3000) });
        const was = this.serverOnline;
        this.serverOnline = resp.ok;
        this._updateStatus();
        if (!was && this.serverOnline) await this._initSession();
        if (this.serverOnline && (!was || this._pullNeeded)) await this._pullAnnotations();
        if (this.serverOnline) await this._flushOutbox();
      } catch {
        this.serverOnline = false;
        this._updateStatus();
      }
    },
    async _initSession() {
      if (!this.serverOnline) return;
      try {
        const request = this._sameOriginMutationRequest("/sessions");
        if (!request) {
          this._setSyncUnavailable("Sync unavailable: endpoint must be same-origin");
          return;
        }
        const resp = await fetch(request.url, {
          method: "POST", headers: request.headers, credentials: "same-origin",
          body: JSON.stringify({ url: window.location.href, metadata: { tool: "rails-markup" } }),
          signal: AbortSignal.timeout(5000)
        });
        if (resp.ok) {
          const data = await resp.json();
          this.sessionId = data.id;
        }
      } catch (e) { console.warn("[rails-markup] session init failed:", e); }
    },
    async _synchronizeCurrentPage(initializeSession) {
      if (!this.serverOnline) return;
      if (initializeSession) await this._initSession();
      await this._pullAnnotations();
      await this._flushOutbox();
    },
    async _pushToServer(annotation) {
      if (!this.serverOnline) return;
      try {
        const request = this._sameOriginMutationRequest(`/sessions/${encodeURIComponent(this.sessionId || "local")}/annotations`);
        if (!request) {
          this._setSyncUnavailable("Sync unavailable: endpoint must be same-origin");
          return;
        }
        await fetch(request.url, {
          method: "POST", headers: request.headers, credentials: "same-origin",
          body: JSON.stringify({
            page_url: this._pageUrl(),
            clientId: annotation.clientId,
            content: annotation.comment,
            intent: annotation.intent,
            severity: annotation.severity,
            selected_text: annotation.selectedText || null,
            target: annotation.element || {},
            metadata: Object.assign(
              { localId: annotation.id, url: annotation.url },
              annotation.screenshot ? { screenshot: annotation.screenshot } : {}
            )
          }),
          signal: AbortSignal.timeout(5000)
        });
      } catch (e) { console.warn("[rails-markup] push failed:", e); }
    },
  });

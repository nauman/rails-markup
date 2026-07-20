# Rails Markup 1.2 Security and Synchronization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship an authenticated, CSRF-protected, server-authoritative Rails Markup toolbar and a credential-contained five-tool MCP interface with durable offline synchronization.

**Architecture:** The mounted Rails engine is authoritative. Its browser API is protected by the host-selected base controller and identifies toolbar records by client UUID; localStorage is a desired-state outbox and cache. MCP targets and credentials come only from trusted configuration, while canonical tool failures remain recoverable in-band.

**Tech Stack:** Ruby 3.x, Rails engine, Active Record, Minitest, vanilla browser JavaScript, Node DOM/system harness, Turbo.

**Design contract:** `docs/superpowers/specs/2026-07-20-security-sync-design.md`

---

### Task 1: Protect and extend the browser API

**Files:**
- Modify: `app/controllers/rails_markup/annotations_controller.rb`
- Modify: `config/routes.rb`
- Modify: `app/models/rails_markup/annotation.rb`
- Modify: `test/controllers/rails_markup/annotations_controller_test.rb`
- Modify: `test/controllers/rails_markup/dashboard_controller_test.rb`
- Modify: `test/application_system_test_case.rb`
- Modify: `test/system/dashboard_system_test.rb`
- Modify: `test/system/toolbar_system_test.rb`
- Create: `test/dummy/app/controllers/rails_markup_test_auth_controller.rb`
- Create: `test/dummy/app/controllers/rails_markup_test_sessions_controller.rb`
- Create: `test/dummy/app/controllers/rails_markup_test_assets_controller.rb`
- Modify: `test/dummy/app/views/layouts/application.html.erb`
- Modify: `test/dummy/config/routes.rb` (Claude's harness baseline is committed at `50babbf`)
- Modify: `test/dummy/config/initializers/rails_markup.rb`

- [ ] Starting from Claude's committed `50babbf` dummy routes/browser harness, set `base_controller_class = "RailsMarkupTestAuthController"` in the dummy initializer before controller constants load. The test auth controller checks `session[:rails_markup_admin]`; the test session controller renders a real authenticity token and accepts it to establish that session.
- [ ] Add integration and Capybara helpers that GET the session form, extract its authenticity token, POST it, retain the cookie, and send `X-CSRF-Token` on JSON mutations. Wrap forgery-protection cases with saved `ActionController::Base.allow_forgery_protection`, set it to true, and restore it in `ensure`. Because the configured base also protects `DashboardController`, authenticate all existing dashboard controller/system tests in setup; retain explicit unauthenticated cases. These are deliberate post-`50babbf` test edits, not a harness restructure.
- [ ] Write named failing tests for unauthenticated health/pull/mutation, missing-CSRF mutation, and authenticated valid-CSRF mutation. Run the focused file and verify auth tests fail because the toolbar controller still bypasses the configured base and uses `null_session`.
- [ ] Make `RailsMarkup::AnnotationsController` inherit directly from the configured base and declare exception CSRF. Run the auth subset GREEN and commit `fix(api): protect toolbar with host auth and csrf`.
- [ ] Write named failing tests for exact-page GET/order, query separation, UUID PUT create/update, UUID DELETE twice, whitespace/oversized UUID 422, blank POST UUID normalization, and POST metadata rejecting client `author`.
- [ ] Write status-ownership tests: an ordinary PUT containing `status` without `dirtyFields: ["status"]` preserves server status; a PUT with that explicit dirty field may update to a valid status; invalid dirty fields/status return 422.
- [ ] Add a controlled concurrency test where PUT save raises `ActiveRecord::RecordNotUnique`, the controller reloads the UUID winner, applies the same permitted desired state, and returns one record.
- [ ] Run the focused API subset and verify RED for missing routes/actions.
- [ ] Add `GET /api/annotations`, `PUT /api/annotations/:client_uuid`, and `DELETE /api/annotations/:client_uuid` routes before numeric compatibility routes.
- [ ] Implement exact page filtering, deterministic ordering, UUID validation, permitted field ownership, `dirtyFields`-gated status, metadata merge, idempotent destroy, full API representations, and the unique-race reload path.
- [ ] Normalize blank compatibility `clientId` to nil and retain the unique-index race fallback.
- [ ] Run: `bundle exec ruby -Ilib:test test/controllers/rails_markup/annotations_controller_test.rb` and confirm the exact run/assertion count is stable with zero failures.
- [ ] Run: `bundle exec ruby -Ilib:test test/controllers/rails_markup/dashboard_controller_test.rb` and `bundle exec rake test:system`; expected all authenticated baseline and explicit rejection cases pass.
- [ ] Commit: `feat(api): add uuid synchronization endpoints`.

### Task 2: Replace the MCP surface with five safe tools

**Files:**
- Modify: `lib/rails_markup/mcp_server.rb`
- Modify: `lib/rails_markup/mcp_config.rb` only if URL validation belongs at configuration load
- Modify: `test/mcp_server_test.rb`
- Modify: `test/mcp_config_test.rb` only when configuration behavior changes

- [ ] Write schema tests for exactly five advertised tools and no aliases in `tools/list`. Schemas use `additionalProperties: false`: `read(resource, environment?, sessionId?, annotationId?)`; `watch(sessionId?, timeoutSeconds?, batchWindowSeconds?)`; `transition(action, annotationId, summary?, environment?)`; `reply(annotationId, message, environment?)`; `dismiss(annotationId, reason, environment?)`. Require server-side conditional IDs and enum validation. Mark read read-only, transition/reply mutating, dismiss destructive.
- [ ] Verify schema tests RED, define the five tools, run GREEN, and commit `refactor(mcp): advertise five canonical tools`.
- [ ] Write adapter tests for every mapping in the design spec. Aliases remain callable but hidden, reject all unknown keys plus `baseUrl`, `url`, `token`, and `markAcknowledged`, emit redacted deprecation warnings, and never auto-acknowledge reads.
- [ ] Verify adapter tests RED, implement explicit adapters, run GREEN, and commit `fix(mcp): make compatibility adapters safe`.
- [ ] Write validation/routing tests: `watch` rejects production; production requires configured HTTPS; development HTTP is allowed only for `localhost`, IPv4 loopback, or IPv6 loopback; userinfo/query/fragment are rejected; path joining cannot discard or escape the configured mount; no caller argument changes destination or bearer credential.
- [ ] Verify RED, implement trusted target parsing/joining, run GREEN, and commit `fix(mcp): constrain configured remote targets`.
- [ ] Write in-band error tests. Invalid/unknown tool calls return a tool result with camel-case `isError: true` and a steering message; only unknown JSON-RPC methods remain JSON-RPC errors. Malformed incoming JSON-RPC emits a parse-error response and a following ping succeeds. Separately, malformed remote JSON, `URI::InvalidURIError`, `Timeout::Error`, `SocketError`, connection refusal, TLS/HTTP exception, and non-2xx each produce an in-band tool error and a following ping succeeds.
- [ ] Add redaction assertions for bearer tokens, URL userinfo/query, annotation content, and request bodies across stdout/stderr.
- [ ] Verify RED, implement per-request containment and redaction, run GREEN, and commit `fix(mcp): keep tool failures recoverable`.
- [ ] Run: `bundle exec ruby -Ilib:test test/mcp_server_test.rb test/mcp_config_test.rb`.

### Task 3: Implement durable toolbar desired-state synchronization

**Files:**
- Modify: `app/assets/javascripts/rails_markup/toolbar.js`
- Create: `package.json`, `package-lock.json`
- Create: `test/javascript/support/toolbar_harness.mjs`
- Create: `test/javascript/support/fake_fetch.mjs`
- Create: `test/javascript/toolbar_state_test.mjs`
- Create: `test/javascript/toolbar_flush_test.mjs`
- Create: `test/javascript/toolbar_reconciliation_test.mjs`
- Create: `.github/workflows/javascript.yml`

The owned unit harness uses Node's test runner plus `happy-dom`. It evaluates the real IIFE and exposes `window.RailsMarkupToolbar`; the support modules provide deterministic localStorage, fetch promises, online state, and manually advanced timers. It stays independent of Claude's committed Cuprite system harness so deterministic races do not depend on Chrome timing.

#### Task 3A: State schema, page identity, and legacy migration

- [ ] Run `npm install --save-dev --save-exact happy-dom@20.11.0 @hotwired/turbo@8.0.23`, commit the resulting manifest/lock only with the first test slice, and add `npm test` as `node --test test/javascript/*_test.mjs`. Add a separate owned JavaScript workflow that installs from the lockfile and runs `npm test` plus `node --check`, without rewriting Claude's Ruby/system workflow. Turbo is a test-only browser-smoke dependency, not a runtime gem dependency.
- [ ] Write RED tests: page identity is `pathname + search`; every unmapped legacy annotation receives a UUID and queued upsert; mapped legacy records do not requeue; duplicate UUIDs collapse to the newest `updatedAt`/local record; server-only records receive stable numeric display IDs across reload.
- [ ] Run `node --test test/javascript/toolbar_state_test.mjs`; expected RED is missing outbox/query-aware migration behavior.
- [ ] Add `clientId`, `serverId`, `syncState`, `serverUpdatedAt`, `dirtyFields`, and an outbox keyed by UUID; implement deterministic migration/collapse/display-ID allocation.
- [ ] Run the state test GREEN plus `node --check app/assets/javascripts/rails_markup/toolbar.js`; commit `feat(toolbar): persist sync identities and desired state`.

#### Task 3B: Durable local mutations

- [ ] Add RED tests that create/edit/status/delete persist before fetch, coalesce to one current desired state, mark exact dirty fields, and replace a queued upsert with a delete tombstone.
- [ ] Add RED manual-retry tests for terminal upserts and terminal delete tombstones even after the local card has been removed.
- [ ] Run the state test; expected RED is missing durable mutation transitions.
- [ ] Route every local mutation through one persistence/enqueue path and expose a user-visible retry action for `failed` entries/tombstones.
- [ ] Run GREEN and commit `feat(toolbar): queue every local annotation mutation`.

#### Task 3C: Serial flush, response classes, and in-flight races

- [ ] Add RED tests for serial single-flight flushing and coalesced simultaneous health/online/visibility triggers.
- [ ] Add RED race tests: an edit replaces an upsert while fetch is pending; delete replaces an in-flight upsert; the captured older response must not clear the newer entry or resurrect the card. Implement with an immutable entry snapshot plus per-entry revision/equality check before clearing/merging.
- [ ] Add a RED operation-specific DELETE test: an intentional `204 No Content` clears only the matching current tombstone and is successful without JSON. Non-JSON 2xx is an error only for operations such as pull/PUT that require a representation.
- [ ] Add RED classification tests for auth/3xx/HTML 2xx stop with visible auth-required/unavailable state; terminal 400/404/409/422 plus representative generic terminal 405/410/415 setting `syncState: failed` and manual retry; retryable 408/425/429/network/5xx; `Retry-After` capped to maximum delay; bounded exponential backoff reset after success; and malformed successful JSON becoming failed only after the configured attempt limit.
- [ ] Run `node --test test/javascript/toolbar_flush_test.mjs`; expected RED is compatibility POST/create-only behavior.
- [ ] Implement UUID PUT/DELETE, full-response merge/server ID capture, one flush promise, one retry timer, immutable snapshots/revisions, and deterministic classification. A successful PUT clears every sent dirty field and sets `syncState: synced`; terminal failures set `failed`.
- [ ] Run flush tests GREEN and commit `feat(toolbar): flush desired state without race loss`.

#### Task 3D: Pull and field-ownership reconciliation

- [ ] Add RED tests for pull-after-init and pull-before-flush reconnect; a failed pull still flushes a durable outbox, never performs absence deletion, and is retried after a later successful health check.
- [ ] Add RED merge tests: server-only add, server content/thread/identity authority without dirty fields, dirty browser fields surviving pull, explicit dirty status surviving until successful PUT, tombstone non-resurrection, absence deletion only after a complete exact-page pull, stale pull and stale PUT response ignored by `serverUpdatedAt`, and query variants never crossing. Assert server `page_url` is only `pathname + search` while full origin appears only in permitted metadata `url`.
- [ ] Run `node --test test/javascript/toolbar_reconciliation_test.mjs`; expected RED is no pull/reconciliation implementation.
- [ ] Implement the exact design-spec ownership matrix and stale-response checks.
- [ ] Run all three Node files GREEN, syntax check, and commit `feat(toolbar): reconcile browser state with Rails`.

### Task 4: Final security, compatibility, and release verification

**Files:**
- Modify: `CHANGELOG.md`
- Modify: `README.md`
- Modify: `lib/generators/rails_markup/install/templates/auth_controller.rb.erb`
- Modify: `lib/generators/rails_markup/install/templates/initializer.rb.erb`
- Create: `test/system/toolbar_sync_system_test.rb`

- [ ] Update browser auth/CSRF, sync ownership, the five-tool thin-enum MCP contract, compatibility removal after 1.3.0, and the requirement that the configured/generated host base controller must actually authorize.
- [ ] Run isolated new tests, then `bundle exec rake test`.
- [ ] Run JavaScript syntax/behavior/system suites.
- [ ] Build the gem and inspect its contents.
- [ ] Probe anonymous and missing-CSRF browser requests.
- [ ] Probe rejected MCP URL/token overrides and confirm no secret appears in stdout/stderr.
- [ ] Send a malformed MCP request followed by ping and confirm the process answers ping.
- [ ] Serve the pinned `node_modules/@hotwired/turbo/dist/turbo.es2017-umd.js` through the test-only assets controller/route and load it before the toolbar partial in the dummy layout; assert `window.Turbo` exists. This enables the required real Turbo-loaded smoke without adding bfcache hardening to scope.
- [ ] Add `ToolbarSyncSystemTest#test_browser_and_server_converge_in_turbo_host`: authenticate through the shared helper, visit `/host`, create an annotation through the real toolbar UI, assert the `RailsMarkup::Annotation` row, apply a server-side reply/status change, trigger/wait for toolbar pull, and assert the real panel reconciles it.
- [ ] Run: `bundle exec ruby -Itest test/system/toolbar_sync_system_test.rb`; expected 1 system test, 0 failures. Then run `bundle exec rake test:system` for the whole committed harness.
- [ ] Commit: `docs: finalize rails-markup 1.2 security and sync`.

Publication, InventList dependency switching, production credential rotation, and Kamal deployment follow the separately reviewed InventList engine-only plan and require the release/deploy gates described there.

Turbo bfcache lifecycle, Shadow-DOM/style isolation, safe-area/touch-target changes, popup scrolling, and pointer drawing are intentionally moved to `docs/superpowers/plans/2026-07-20-toolbar-browser-hardening.md`; they are not part of this approved security/sync contract.

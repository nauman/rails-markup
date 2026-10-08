# Changelog

All notable changes to this project will be documented in this file.

## [1.5.0] - 2026-10-08

### Added

- List and board cards share a focused feedback modal. Review context, images and replies, acknowledge or resolve feedback without leaving the current view, and close with Escape or a backdrop click. Saved changes refresh the current filters and board columns.
- Optional image attachments support browser tab/window capture, PNG/JPEG/WebP upload and pasted images, with a preview, drawing tools and removal before submission. Capture stops its media tracks after taking one frame; unavailable or cancelled capture offers upload and paste instead.
- Dashboard Options can show or hide the entire floating toolbar for the current browser. Preferences stay in sync across open tabs.
- A local Kuickr example and editable, captioned video walkthrough are available under `examples/`, using `script/demo` and a separate persistent demo database. These development assets are excluded from the gem package.

### Changed

- Compact dashboard rows, counted status tabs and contextual disclosures replace the large dashboard summary. Filters, exports and toolbar preferences live under Options; board help and move controls expand on demand.
- Toolbar settings use accent swatches, corner controls and compact switches. Changing a setting keeps the settings view open and retains keyboard focus.
- Added Sydney, nauman.one and Pavelabs credits to the default dashboard and README.

### Fixed

- The selected accent now colors the whole floating toolbar, including hover and annotation states.
- Hiding the floating toolbar removes all its controls while keeping annotations and synchronization available.
- Annotation pins stay inside the viewport on initial render and resize.
- Board cards open their feedback, status moves update counts and empty states, and the help popover stays inside the page.
- Standalone dashboard filtering works without Turbo, and the local demo's legacy login URL redirects to its login form.

No database migration is required. Image capture uses the browser's screen-sharing permission flow rather than automatic DOM-to-image rendering.

## [1.4.7] - 2026-08-30

### Fixed

- The installer now prompts for a nested mount prefix when `--mount-path` is omitted, and it normalizes explicit paths like `/admin/rails-markup`, `/dashboard/rails-markup`, or `/rails-markup` into the generated route and MCP config.
- The MCP and CLI fallback mount path now use `/admin/rails-markup` instead of the legacy `/admin/annotations`, so new installs and local tooling stay aligned with the generated route.
- The public landing/demo FAB icon is smaller, matching the toolbar sizing cleanup and improving the visual balance of the demo chrome.

## [1.4.6] - 2026-08-24

### Fixed

- The browser toolbar now exposes a visible settings control in the UI, not just inside the annotations panel. Toolbar presentation settings are persisted per endpoint and override init-time defaults on startup.
- The floating annotation button is smaller by default, and the toolbar badge now sits on the panel toggle instead of the FAB.
- The dashboard close button now returns to the list outside the split-panel layout instead of blanking the page.

## [1.4.5] - 2026-07-27

### Fixed

- **Keyboard focus is preserved when a custom menu closes involuntarily.** When a portaled intent/severity/status menu closed due to panel/window scroll, resize, or Tab while an option had focus, focus fell to `<body>`; it now returns to the menu's trigger button, so keyboard/`Tab` navigation stays deterministic (found in a post-release review of #4's menus).

## [1.4.4] - 2026-07-27

Internal refactor only — no behavior change.

### Changed

- The browser toolbar source is split from a single ~2,600-line `toolbar.js` into focused modules under `app/assets/javascripts/rails_markup/toolbar/` (`00-core`, `10-styles`, `20-dom`, `30-menu`, `40-events`, `50-sync`, `60-render`, `90-init`). They are concatenated in order into the same single inline `<script>` by `RailsMarkup::ToolbarSource` (and identically by the JS test harness) — still no bundler, no build step, self-contained in any Rails app. Runtime behavior is unchanged: every method body is identical and byte-for-byte preserved; only the ordering (methods regrouped behind `Object.assign`) differs, so the concatenated bytes are not literally identical to the previous single file.

## [1.4.3] - 2026-07-27

Fixes #4 — annotation popup/status dropdowns no longer break under host UI frameworks. Community contribution by @hughg12311, with review follow-ups.

### Fixed

- **Popup intent/severity and panel status controls are now custom button menus** under `#rm-toolbar-root` instead of native `<select>`s, so host CSS *and* host select-enhancers (Materialize `FormSelect`, Select2, etc.) can't restyle or duplicate them (the reported "double underlined dropdown" symptom). Hidden inputs keep the same ids, so the `.value` API and the revision/`baseRevision` sync path are unchanged.
- **Full keyboard model** on the menus: open focuses the selected option; Arrow/Home/End navigate; Enter/Space select; Escape closes and restores focus to the trigger; Tab closes without trapping; `aria-expanded`/`aria-selected` stay in sync.
- **Menus escape the panel's `overflow`/`backdrop-filter` containing block** by portaling the open list to `#rm-toolbar-root` and positioning it viewport-fixed (flip-up when needed), so status menus on lower cards are no longer clipped. Delegation is preserved via `data-menu-owner`.
- **Escape closes an open menu regardless of annotation mode** — the keydown handler is bound once and torn down in `destroy()`.

## [1.4.2] - 2026-07-26

## [1.4.2] - 2026-07-26

Fifth-round audit follow-ups — closes two client-side sync-reconciliation races. Toolbar-only; no server or schema change.

### Fixed

- **Delete-while-a-PUT-is-in-flight no longer resurrects the record:** when a superseded upsert succeeds, the causally-later tombstone's `baseRevision` is durably advanced to the server's new revision before the DELETE is sent, so the delete applies at the right revision instead of hitting a stale `409` that restored the annotation.
- **A deleted-then-edited annotation recreates correctly:** on the single permitted missing-record retry (`409` with `annotation: null`), the toolbar now resends the complete desired state with all required fields, instead of replaying a narrow edit delta that failed validation and left the outbox permanently stuck.
- Corrected the in-flight-delete test to model the real DELETE `409`/`204` revision contract (it previously mocked an impossible `204`, masking the race above).

## [1.4.1] - 2026-07-26

Fourth-round audit follow-ups — completes the revision protocol and closes concurrency edges. No schema change (1.4.0's migration still applies).

### Fixed

- **Browser DELETE participates in optimistic concurrency:** it now requires `baseRevision`, locks the row, and returns `409` (with the current record) on mismatch instead of destroying — so a stale tab can't delete an annotation that an agent just replied to/resolved. Stays idempotent when the record is already gone.
- **Dashboard writes bump `revision`:** board `transition` (under a row lock) and `dismiss_all` now increment `revision`, so a concurrent toolbar edit conflicts (409) instead of silently overwriting them or being lost.
- **Toolbar 409 handling no longer loops:** it consumes the record returned in the conflict body to rebase; a moved record reconciles without a page-pull loop, and a genuinely missing record stops retrying instead of conflicting forever.
- **Thread growth is bounded** on both the ActiveRecord model (max entries + per-entry length) and the standalone store (per-message byte cap + thread bytes counted toward the aggregate memory cap). MCP `summary`/`message`/`reason` advertise and enforce a 5000-char/byte maximum.
- **Standalone store enforces valid status transitions** (idempotent on same terminal state, rejects reopening) — mirrors the model's state machine.
- **Legacy localStorage migration is provenance-safe:** only the exact current-page key auto-migrates; the ambiguous bare `rm-annotations` key is left intact (recoverable by another mount) unless an explicit `legacyStorageEndpoint` designates this toolbar to claim it.

### Docs

- Corrected the 1.4.0 upgrade note: engine migrations must be copied first (`rails railties:install:migrations FROM=rails_markup`) before `rails db:migrate`.

## [1.4.0] - 2026-07-26

Third-round audit hardening: concurrency, credential provenance, and a safe upgrade path for the browser sync protocol.

**Upgrade note:** this release adds a `revision` column to the annotations table. Engine migrations are not auto-run, so copy then migrate:

```bash
bin/rails railties:install:migrations FROM=rails_markup
bin/rails db:migrate
```

The browser toolbar now sends a `baseRevision` and handles `409 Conflict` by re-pulling; the bundled toolbar and server upgrade together.

### Security

- **CLI binds a production URL, token, and mount path to a single config scope** (credential provenance), replacing the per-key cross-scope merge from 1.3.0 that could pair a repo-local URL with a global token. A local dev-only config still doesn't shadow global production credentials.
- **A blank `api_token` now disables the external API** instead of authenticating every request (`secure_compare("", "")` returned true).
- **Standalone store CORS** reflects only validated loopback request origins, so a browser app on `localhost:3000` can talk to the store on `4747` (and non-loopback origins get no allow-origin header).

### Fixed

- **Optimistic concurrency on the browser upsert:** the full-state PUT now applies only the client's declared `dirtyFields` and checks `baseRevision`, returning `409` (with the current record) instead of clobbering a concurrent edit; the server bumps `revision` on every applied change.
- **SSE broadcast no longer holds the store mutex** during network writes — one slow subscriber can't block session creation, reads, or other subscribers.
- **`acknowledge!` runs under the row lock**, so it can't reopen a concurrently resolved/dismissed record.
- **localStorage upgrade migrates real pre-1.3 data:** the bare `rm-annotations` key and legacy `rm-annotations:/path` keys (annotations *and* pending outbox) are folded once into the endpoint-namespaced store and then cleared, instead of being ignored (which dropped locally-cached annotations and offline mutations).
- **Standalone store bounds per-session memory** (per-session annotation count + aggregate byte cap, with clear `422`/`507` responses and basic field validation).
- **MCP `watch` returns a clear "unsupported" error in proxy/mcp-only mode** instead of blocking stdio for 120s and returning nothing.
- **Toolbar tears down on `turbo:before-cache`**, so Turbo's page cache can't restore a dead toolbar root that `init()` would skip re-binding.
- **Install generator validates `--table-name`** against a safe SQL identifier, and the legacy toolbar-block upgrade regex now matches only the exact generated block.

## [1.3.0] - 2026-07-26

Security & correctness hardening from a full second-round audit.

### Security

- **Standalone HTTP store server binds to loopback (127.0.0.1) by default.** It is unauthenticated, so it no longer listens on all interfaces; use `bin/markup server --host 0.0.0.0` to deliberately expose it on the LAN.
- **External API development auth is now configurable.** It still skips the token in development by default (so you can reach it from another device), but `config.require_api_token_in_development = true` locks it down on untrusted networks. This bypass allows unauthenticated reads and writes, now documented.
- **CSV export neutralizes spreadsheet formula injection** — cells beginning `= + - @` or a control char are prefixed with `'`.
- **CLI refuses to send the production bearer token over `http://`** — production URLs must use HTTPS.
- **Standalone store enforces its session hard cap** even when all sessions are fresh (was unbounded).

### Fixed

- MCP env resolution merges configs per-key (local → global → codex) instead of returning the first non-empty config, so a local dev-only config no longer shadows global production credentials.
- Thread mutations (`resolve!` / `dismiss!` / `add_reply!`) run under a row lock, preventing concurrent replies/resolutions from silently overwriting each other.
- `page_url` column is `string(2048)` to match the model's length validation (the default 255 raised DB errors on PostgreSQL/MySQL for long URLs); index uses a MySQL-safe prefix.
- Install generator upgrades a pre-1.2.3 public toolbar layout block to the admin gate on re-run instead of skipping it.
- Toolbar suppresses press events (mousedown/touchstart) in annotation mode so host controls don't act before the click is blocked.
- Toolbar tears down after a logout Turbo visit whose new body omits the (admin-gated) partial, instead of recreating itself and exposing cached annotations.
- Browser localStorage is namespaced by endpoint, so different users/mounts on the same origin no longer leak or clobber each other's annotations; old unnamespaced data is ignored.
- Legacy offline outbox entries are upgraded to the full sync envelope (top-level `clientId`/`revision`/`syncState`) before flush, fixing requests to `/annotations/undefined`.

## [1.2.4] - 2026-07-26

### Fixed

- Popup intent/severity `<select>` controls now force `display:inline-block` (plus `visibility`/`opacity`), so hosts that hide unstyled selects — e.g. Materialize's `select:not(.browser-default){display:none}` — no longer make the dropdowns disappear. Follow-up to #4, found in review.

## [1.2.3] - 2026-07-26

### Fixed

- Install generator now injects the toolbar behind an admin gate (`current_user.admin?`) instead of a partial-existence check, so the FAB/toolbar chrome no longer ships to logged-out or non-admin users (#3).
- `bin/markup` now requires `bundler/setup` before the CLI, fixing a `LoadError` when rails-markup is installed from a git source (#2).
- Procfile.dev injection ensures a leading newline so the `markup:` process no longer glues onto a last line that lacks a trailing newline (#1).
- Popup intent/severity `<select>` controls are isolated from host form CSS with higher-specificity hard resets (border/background/box-shadow/appearance), preventing host underline styles from bleeding through (#4).

## [1.2.2] - 2026-07-23

### Fixed

- Status transitions (`acknowledge!` / `resolve!` / `dismiss!`) are now idempotent — re-applying the same status (double-click, MCP re-run) is a no-op instead of raising and returning HTTP 500.

## [1.2.1] - 2026-07-21

### Fixed

- CSV export preserves the dashboard's recent (created_at desc) order — `find_each` ignored `ORDER BY`.

### Changed

- Repository moved to https://github.com/nauman/rails-markup; homepage/source/changelog metadata updated.

## [1.2.0] - 2026-07-21

### Added

- `toolbar_enabled` configuration to show or hide the entire annotation toolbar system.
- `fab_visible` configuration to hide the floating action button independently, while pins and the panel stay active; exposed as a step in the setup wizard.
- Stable per-annotation client UUIDs with a database uniqueness constraint for safe request replay.
- Repeatable `rails_markup:client_uuids:repair` and `rails_markup:client_uuids:verify` tasks for rolling upgrades.
- Keyset (cursor) pagination for the dashboard "Load more".
- `thor` and `lipgloss` declared as explicit runtime dependencies; `csv` pinned.
- Install generator `--table-name` option that writes the chosen table into both the migration and `config.table_name` for fresh custom-table installs.
- Authenticated exact-page pull plus idempotent UUID PUT/DELETE endpoints for durable browser synchronization.
- A Rails-authoritative desired-state outbox with offline create/edit/status/delete replay and server reconciliation.
- Five canonical thin-enum MCP tools: `read`, `watch`, `transition`, `reply`, and destructive `dismiss`.
- A real Turbo-loaded Cuprite system test covering browser creation and server-to-panel reconciliation.

### Changed

- Minimum Ruby is now 3.2 (aligns with the resolved Rails 8.1 baseline); CI matrix is 3.2–3.4.
- The dashboard and toolbar API now share the configured host authentication boundary and Rails CSRF protection.
- MCP destinations and bearer credentials now come only from trusted configuration; legacy aliases remain hidden adapters and will be removed after 1.3.0.
- Generated authentication denies non-admin users by default and requires explicit host-policy customization when `current_user.admin?` is not the application contract.

### Fixed

- Deterministic dashboard ordering for annotations with identical timestamps.
- Dashboard "Load more" no longer repeats a row when annotations arrive between page requests (offset → keyset pagination).
- The `client_uuid` migration now honors a custom `config.table_name` instead of silently skipping renamed tables (which had defeated create-time deduplication).
- Legacy per-page localStorage migration no longer discards annotations whose ids collide across pages.
- Toolbar panel and popup no longer overflow small mobile screens.
- Generated install migration uses `json` on SQLite/MySQL instead of PostgreSQL-only `jsonb`, so fresh installs no longer fail on non-Postgres databases.
- Dashboard "Load more" now requires a valid cursor; a stale `?page=` or malformed cursor returns an empty page instead of re-serving (and duplicating) page one.
- Creating an annotation while a panel filter is active no longer shows the new card under a non-matching filter.
- Kanban board transitions now reload on a rejected server response (previously only network errors were caught, so a 4xx left the card out of sync).
- Kanban board cards gain a status `<select>` so touch devices can change status without drag-and-drop.
- CLI test load order so the complete suite can run in one process.
- Repeated Turbo execution no longer replaces the toolbar singleton or leaks navigation listeners.
- Legacy numeric/string toolbar IDs now map to deterministic canonical UUIDs scoped by session, preserving exact replay and conflict detection without colliding after local storage is reset.
- Existing-install UUID backfill remains nullable during mixed-version deployment; invalid rows fail pulls closed and can be repaired idempotently before a later explicit `NOT NULL` contract migration.
- Client UUIDs are normalized to lowercase across POST/PUT/DELETE paths; repair resolves case-fold collisions deterministically and requires a full, unpredicated, unprefixed unique index.
- Toolbar mutations persist before network I/O, coalesce safely, retain in-flight replacements, and classify authentication, terminal, retryable, and malformed responses without losing desired state.
- Pull reconciliation preserves dirty browser-owned fields and delete tombstones while accepting server-owned thread, identity, timestamps, and agent status/replies.
- MCP rejects URL/token overrides, confines remote failures in-band, redacts secrets, and remains live after malformed JSON-RPC or remote responses.

## [1.0.0] - 2026-03-12

First stable release. Full annotation lifecycle from browser toolbar through AI agent resolution.

### Added

- **Annotation toolbar** — point-and-click element annotation with intent (fix/change/question/approve) and severity (suggestion/important/blocking)
- **Screenshot capture** — element screenshots using SVG foreignObject with drawing tools (arrows, rectangles, highlights, undo)
- **Dashboard** — list view with status filters, search, author filter, load-more pagination
- **Kanban board** — drag-and-drop status transitions across 4 columns
- **Detail panel** — two-column layout with sticky detail sidebar, thread display, inline actions
- **Export** — CSV and JSON downloads respecting current filters
- **Author attribution** — `author_name_method` config (Symbol or Proc) for display names
- **Notification hook** — `on_create_callback` config fires after annotation creation
- **Bulk actions** — dismiss all pending/acknowledged annotations
- **External API** — token-authenticated REST endpoints for MCP production tools
- **MCP server** — 11 JSON-RPC tools over stdio (list, get, watch, acknowledge, resolve, dismiss, reply + production variants)
- **CLI** — `server`, `mcp`, `init`, `configure`, `status`, `fetch`, `setup-production` commands
- **Setup wizard** — interactive TUI (`bin/markup init`) with Bubbletea for guided configuration
- **Install/uninstall generators** — migration, initializer, auth controller, bin wrapper, route mount, toolbar injection
- **Turbo compatibility** — `turbo:load` and `turbo:frame-render` listeners for SPA navigation
- **Host layout integration** — `dashboard_layout` config to embed dashboard in host app's admin layout
- **Toolbar customization** — accent color (5 options), position (4 corners), size (3 sizes)

### Configuration Options

```ruby
RailsMarkup.configure do |config|
  config.base_controller_class = "Admin::BaseController"
  config.api_token = Rails.application.credentials.dig(:rails_markup, :api_token)
  config.author_name_method = :name
  config.on_create_callback = ->(ann) { notify(ann) }
  config.toolbar_accent = "indigo"      # indigo, amber, blue, emerald, rose
  config.toolbar_position = "bl"        # bl, br, tl, tr
  config.toolbar_size = "default"       # slim, compact, default
  config.enable_screenshots = true
  config.per_page = 25
  config.return_url = "/admin"
  config.dashboard_layout = "application"
end
```

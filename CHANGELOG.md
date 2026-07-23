# Changelog

All notable changes to this project will be documented in this file.

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

# Changelog

All notable changes to this project will be documented in this file.

## [1.2.0] - Unreleased

### Added

- `toolbar_enabled` configuration to show or hide the entire annotation toolbar system.
- `fab_visible` configuration to hide the floating action button independently, while pins and the panel stay active; exposed as a step in the setup wizard.
- Stable per-annotation client UUIDs with a database uniqueness constraint for safe request replay.
- Keyset (cursor) pagination for the dashboard "Load more".
- `thor` and `lipgloss` declared as explicit runtime dependencies; `csv` pinned.

### Fixed

- Deterministic dashboard ordering for annotations with identical timestamps.
- Dashboard "Load more" no longer repeats a row when annotations arrive between page requests (offset → keyset pagination).
- The `client_uuid` migration now honors a custom `config.table_name` instead of silently skipping renamed tables (which had defeated create-time deduplication).
- Legacy per-page localStorage migration no longer discards annotations whose ids collide across pages.
- Toolbar panel and popup no longer overflow small mobile screens.
- CLI test load order so the complete suite can run in one process.
- Repeated Turbo execution no longer replaces the toolbar singleton or leaks navigation listeners.

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

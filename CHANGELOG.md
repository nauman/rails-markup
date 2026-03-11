# Changelog

All notable changes to this project will be documented in this file.

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

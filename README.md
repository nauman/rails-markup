# Rails Markup

Point-and-click annotation tool for Rails apps. Click any element, describe what needs to change, and your AI agent reads and acts on your feedback via MCP.

**v1.0** — Author attribution, export, search, screenshots with drawing tools, kanban board, notification hooks.

## How it works

1. **Install the gem** — adds migration, toolbar, auth controller, and routes
2. **Open your app** — the annotation toolbar appears as a floating button
3. **Click any element** — hover to highlight, click to annotate with screenshots
4. **Draw on screenshots** — arrows, rectangles, highlights on captured elements
5. **Agent reads it** — AI calls `rails_markup_get_all_pending` via MCP
6. **Agent fixes it** — resolves the annotation and moves on

## Install

```ruby
# Gemfile
gem "rails-markup", github: "inventlist/rails-markup", require: "rails_markup"
```

```bash
bundle install
rails generate rails_markup:install
rails db:migrate
```

The generator creates:

| File | Purpose |
|------|---------|
| `db/migrate/*_create_rails_markup_annotations.rb` | Annotations table |
| `config/initializers/rails_markup.rb` | Configuration |
| `app/controllers/rails_markup_auth_controller.rb` | Auth controller |
| `bin/markup` | CLI wrapper |
| Route mount | Engine at `/admin/annotations` |
| Toolbar injection | `<%= render "rails_markup/shared/toolbar" %>` in your layout |

### Generator options

```bash
rails generate rails_markup:install \
  --mount-path=/admin/annotations \
  --base-controller=Admin::BaseController \
  --layout=application
```

### Uninstall

```bash
rails generate rails_markup:uninstall
# Add --remove-migration to also delete the migration file
```

## Configuration

```ruby
# config/initializers/rails_markup.rb
RailsMarkup.configure do |config|
  # Auth controller for dashboard
  config.base_controller_class = "Admin::BaseController"

  # External API token (for MCP production tools)
  config.api_token = Rails.application.credentials.dig(:rails_markup, :api_token)

  # Author display name from current_user
  config.author_name_method = :name
  # Or use a Proc:
  # config.author_name_method = ->(user) { "#{user.first_name} #{user.last_name}" }

  # Callback fired after each annotation is created
  config.on_create_callback = ->(annotation) {
    SlackNotifier.notify("Feedback on #{annotation.page_url}: #{annotation.content}")
  }

  # Toolbar accent color: indigo, amber, blue, emerald, rose
  config.toolbar_accent = "indigo"

  # Element screenshots (default: true)
  config.enable_screenshots = true

  # Dashboard pagination (default: 25)
  config.per_page = 25

  # "Back to app" link
  config.return_url = "/admin"
end
```

## Dashboard

Visit `/admin/annotations` for the full dashboard:

- **List view** — status filters, search, author filter, pagination
- **Board view** — kanban with drag-and-drop status transitions
- **Export** — CSV and JSON downloads (respects current filters)
- **Detail panel** — full content, metadata, screenshots, thread
- **Bulk actions** — dismiss all pending/acknowledged

### Search & Filters

- **Text search** — searches annotation content and selected text
- **Author filter** — filter by who created the annotation
- **Page URL filter** — filter by annotated page
- **Status pills** — pending, acknowledged, resolved, dismissed

## Screenshots & Drawing

When you click an element, the toolbar captures a screenshot using SVG foreignObject. Before submitting, you can draw on it:

- **Arrow** — click and drag to draw red arrows
- **Rectangle** — click and drag for red outline boxes
- **Highlight** — freehand semi-transparent yellow strokes
- **Undo** — remove the last drawing operation

Screenshots are stored as base64 in annotation metadata and displayed in the dashboard detail view.

## CLI

```bash
bin/markup server                    # HTTP + MCP server
bin/markup mcp                       # MCP-only server (stdio)
bin/markup fetch                     # Fetch pending from dev
bin/markup fetch --env=production    # Fetch from production
bin/markup configure                 # Set .mcp.json env vars
bin/markup status                    # Show config (tokens masked)
bin/markup setup-production --url=URL  # Generate token + configure
```

## MCP Setup

Add to `.mcp.json`:

```json
{
  "mcpServers": {
    "rails-markup": {
      "type": "stdio",
      "command": "ruby",
      "args": ["bin/markup", "mcp"],
      "env": {
        "RAILS_MARKUP_DEV_URL": "http://localhost:3000",
        "RAILS_MARKUP_PROD_URL": "https://yourapp.com",
        "RAILS_MARKUP_PROD_TOKEN": "your-prod-api-token"
      }
    }
  }
}
```

### MCP Tools

| Tool | Purpose |
|------|---------|
| `rails_markup_get_all_pending` | All pending annotations |
| `rails_markup_get_pending` | Pending for one session |
| `rails_markup_watch_annotations` | Block until new annotations arrive |
| `rails_markup_acknowledge` | Mark as seen |
| `rails_markup_resolve` | Resolve with summary |
| `rails_markup_dismiss` | Dismiss with reason |
| `rails_markup_reply` | Add reply to thread |
| `rails_markup_fetch_production` | Fetch pending from production |
| `rails_markup_resolve_production` | Resolve production annotation |
| `rails_markup_dismiss_production` | Dismiss production annotation |
| `rails_markup_reply_production` | Reply to production annotation |

## Annotation Data

Each annotation includes:

- **Content** — what needs to change (max 5000 chars)
- **CSS selector** — `div#hero.max-w-xl`
- **CSS path** — `body > main > div:nth-of-type(2) > div#hero`
- **Bounding box** — `{ top, left, width, height }`
- **Nearby text** — first 80 chars of element text
- **Selected text** — highlighted text before clicking
- **Screenshot** — element capture with optional drawings
- **Author** — who created it (via `author_name_method`)
- **Intent** — `fix`, `change`, `question`, or `approve`
- **Severity** — `suggestion`, `important`, or `blocking`

## Architecture

```
Browser Toolbar                    AI Agent (Claude Code, Cursor)
    |                                    |
    | Same-origin API                    | MCP (stdio JSON-RPC)
    | (POST /api/*)                      | or CLI (bin/markup fetch)
    v                                    v
+----------------------------------------------------------+
|                  Rails Engine                             |
|                                                          |
|  Toolbar     →  Annotations    →  Dashboard              |
|  (vanilla JS)   (ActiveRecord)    (list + board views)   |
|                       ↑                                  |
|              External API (/external/*)                   |
|              (token-authenticated, used by MCP)           |
+----------------------------------------------------------+
```

## Development

```bash
git clone https://github.com/inventlist/rails-markup
cd rails-markup && bundle install
bundle exec ruby -Ilib:test test/**/*_test.rb
```

## License

MIT. See [LICENSE](LICENSE).

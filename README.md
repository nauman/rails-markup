# Rails Markup

Point-and-click annotation tool for Rails apps. Click any element, describe what needs to change, and your AI agent reads and acts on your feedback via MCP.

**v1.0** — Author attribution, export, search, screenshots with drawing tools, kanban board, notification hooks.

## How it works

1. **Install the gem** — adds migration, toolbar, auth controller, and routes
2. **Open your app** — the annotation toolbar appears as a floating button
3. **Click any element** — hover to highlight, click to annotate with screenshots
4. **Draw on screenshots** — arrows, rectangles, highlights on captured elements
5. **Agent reads it** — AI calls `rails_markup_read` via MCP
6. **Agent fixes it** — resolves the annotation and moves on

## Install

```ruby
# Gemfile
gem "rails-markup", github: "nauman/rails-markup", require: "rails_markup"
```

```bash
bundle install
rails generate rails_markup:install
rails db:migrate
```

When upgrading an existing installation, copy and run new engine migrations:

```bash
bin/rails railties:install:migrations FROM=rails_markup
bin/rails db:migrate
```

### Rails Markup 1.2 rolling UUID upgrade

The 1.2 upgrade migration adds, repairs, and uniquely indexes `client_uuid`, but
deliberately leaves the column nullable while old application instances may
still be serving traffic. Fresh installs create it as `NOT NULL` immediately.

For a rolling upgrade:

1. Run the copied migrations and deploy 1.2 to every application instance.
2. Wait until all old pre-1.2 instances are drained and have stopped.
3. Repair any rows written during the mixed-version window, then verify:

```bash
bin/rails rails_markup:client_uuids:repair
bin/rails rails_markup:client_uuids:verify
```

Both commands are safe to repeat. A pull containing any lingering blank or
noncanonical identity returns `503` without mutating data. Do not add a
`NOT NULL` constraint until verification stays green after old instances are
drained; that explicit contract migration belongs in a later release.

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

### Authentication and browser synchronization

The generated `RailsMarkupAuthController` protects both the mounted dashboard
and the toolbar API. It denies access unless `current_user.admin?` is true;
customize `authorize_rails_markup!` if your host uses another authorization
policy. The configured base controller must actually enforce authorization.
Choosing a public controller makes both interfaces public.

The toolbar uses the same host authentication boundary as the dashboard and
sends normal Rails CSRF tokens on every mutation. Keep `csrf_meta_tags` in the
host layout. Rails is authoritative; localStorage is an offline cache and a
durable desired-state outbox, keyed by a client UUID.

During reconciliation, browser-owned content, intent, severity, selection,
target, permitted metadata, and an explicitly dirty status remain local until a
successful UUID PUT. Server-owned thread, author/user identity, and timestamps
always win. A complete exact-page pull may remove a synced local record absent
from Rails, but never removes pending upserts or delete tombstones.

### Uninstall

```bash
rails generate rails_markup:uninstall
# Add --remove-migration to also delete the migration file
```

## Configuration

```ruby
# config/initializers/rails_markup.rb
RailsMarkup.configure do |config|
  # Auth controller for dashboard and toolbar API; it must authorize access.
  config.base_controller_class = "RailsMarkupAuthController"

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

  # Show or hide the annotation toolbar and FAB (default: true)
  config.toolbar_enabled = true

  # FAB corner: bl, br, tl, tr; size: slim, compact, default
  config.toolbar_position = "bl"
  config.toolbar_size = "default"

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

- **List view** — status filters, search, author filter, load-more pagination
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
# Setup
bin/markup init                        # Interactive setup wizard (TUI)
bin/markup configure                   # Set .mcp.json env vars
bin/markup status                      # Show config (tokens masked)
bin/markup setup-production --url=URL  # Generate token + configure

# Server
bin/markup server                      # HTTP + MCP server
bin/markup mcp                         # MCP-only server (stdio)

# Annotations (match MCP tool verbs)
bin/markup pending                     # Fetch pending from dev
bin/markup pending --production        # Fetch from production
bin/markup resolve 42 --summary "..."  # Resolve an annotation
bin/markup dismiss 42 --reason "..."   # Dismiss an annotation
bin/markup reply 42 "message"          # Reply to an annotation
bin/markup acknowledge 42              # Mark as acknowledged
bin/markup watch                       # Poll for new annotations
bin/markup watch --production          # Watch production

# Info
bin/markup sessions                    # Session info (MCP only)
bin/markup session ID                  # Session detail (MCP only)
```

### Setup Wizard

Run `bin/markup init` for an interactive setup that walks you through:

1. Toolbar accent color (indigo, amber, blue, emerald, rose)
2. Toolbar position (bottom-left, bottom-right, top-left, top-right)
3. Toolbar size (slim, compact, default)
4. Screenshot capture (on/off)
5. Production URL (optional)

Writes `config/initializers/rails_markup.rb` and updates `.mcp.json` automatically.

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

### MCP tools (five canonical thin-enum tools)

The MCP server advertises exactly five tools. Their schemas reject unknown
arguments and use small enums instead of multiplying environment-specific tool
names:

| Tool | Contract |
|------|----------|
| `rails_markup_read` | Read `pending`, `sessions`, `session`, or `annotation`; never acknowledges |
| `rails_markup_watch` | Watch development annotations with bounded timeout/window |
| `rails_markup_transition` | `acknowledge` or `resolve` an annotation |
| `rails_markup_reply` | Add an agent reply |
| `rails_markup_dismiss` | Destructively dismiss with a reason |

`environment` is `development` or `production` where supported. Production URL
and bearer credentials come only from trusted process configuration.
Caller-supplied URL and token overrides are rejected and are never forwarded.

### Legacy MCP compatibility

Legacy names remain hidden but callable as explicit, warning-emitting adapters
during the 1.2/1.3 compatibility window. They never restore caller-controlled
credentials or mutating reads. They will be removed after 1.3.0; migrate clients
to the five canonical tools above.

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
    | Authenticated same-origin API      | MCP (stdio JSON-RPC)
    | (pull + UUID PUT/DELETE, CSRF)     | or CLI (bin/markup pending)
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
git clone https://github.com/nauman/rails-markup
cd rails-markup && bundle install
bundle exec ruby -Ilib:test test/**/*_test.rb
```

## License

MIT. See [LICENSE](LICENSE).

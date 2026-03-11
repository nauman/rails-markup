# Rails Markup

Point-and-click annotation tool for AI agents. Annotate your Rails app in the browser, and your AI agent reads and acts on your feedback via MCP.

## How it works

1. **Install the gem** — adds migration, toolbar, auth controller, and routes
2. **Open your app** — the annotation toolbar appears as a floating button (bottom-left)
3. **Click any element** — hover to highlight, click to annotate, describe what needs to change
4. **Agent reads it** — your AI calls `rails_markup_get_all_pending` via MCP or you run `bin/markup fetch`
5. **Agent fixes it** — the agent resolves the annotation and moves on to the next

## Install

Add to your Gemfile:

```ruby
# Development only (recommended)
gem "rails-markup", github: "inventlist/rails-markup", require: "rails_markup", group: :development

# Or all environments (enables admin feedback on production)
gem "rails-markup", github: "inventlist/rails-markup", require: "rails_markup"
```

```bash
bundle install
rails generate rails_markup:install
rails db:migrate
```

The install generator creates:

| File | Purpose |
|------|---------|
| `db/migrate/*_create_rails_markup_annotations.rb` | Annotations table |
| `config/initializers/rails_markup.rb` | Configuration (auth, accent color, etc.) |
| `app/controllers/rails_markup_auth_controller.rb` | Auth controller (inherits your admin auth) |
| `bin/markup` | CLI wrapper |
| Route mount | Engine at `/admin/annotations` |
| Toolbar injection | `<%= render "rails_markup/shared/toolbar" %>` in your layout |

### Generator options

```bash
rails generate rails_markup:install \
  --mount-path=/admin/annotations \     # Engine route (default)
  --base-controller=Admin::BaseController \  # Auth parent class
  --layout=application                  # Layout for toolbar injection
```

### Uninstall

```bash
rails generate rails_markup:uninstall
# Add --remove-migration to also delete the migration file
```

## CLI

```bash
bin/markup server              # HTTP + MCP server (standalone mode)
bin/markup mcp                 # MCP-only server (stdio, for .mcp.json)
bin/markup fetch               # Fetch pending annotations from dev
bin/markup fetch --env=production  # Fetch from production
bin/markup configure           # Set .mcp.json env vars
bin/markup status              # Show current .mcp.json config
```

### Fetch examples

```bash
# Fetch from local dev server
bin/markup fetch

# Fetch from production
bin/markup fetch --env=production

# Override URL/token
bin/markup fetch --url=http://localhost:3000 --token=mytoken
```

## MCP Setup

Add to `.mcp.json` (Claude Code, Cursor, or any MCP client):

```json
{
  "mcpServers": {
    "rails-markup": {
      "type": "stdio",
      "command": "ruby",
      "args": ["bin/markup", "mcp"],
      "env": {
        "RAILS_MARKUP_DEV_URL": "http://localhost:3000",
        "RAILS_MARKUP_DEV_TOKEN": "your-dev-api-token",
        "RAILS_MARKUP_PROD_URL": "https://yourapp.com",
        "RAILS_MARKUP_PROD_TOKEN": "your-prod-api-token"
      }
    }
  }
}
```

Or generate it:

```bash
bin/markup configure \
  --dev-url=http://localhost:3000 \
  --dev-token=YOUR_DEV_TOKEN \
  --prod-url=https://yourapp.com \
  --prod-token=YOUR_PROD_TOKEN
```

### How tokens work

Tokens authenticate the MCP server against your app's internal API. Generate them in Rails console:

```ruby
# If using InternalApiToken model
InternalApiToken.create!(label: "Rails Markup", scopes: ["annotations:read", "annotations:manage"])

# Or use Rails credentials
Rails.application.credentials.dig(:rails_markup, :api_token)
```

## MCP Tools

When `RAILS_MARKUP_DEV_URL` is set, the local tools automatically proxy to your dev server's database instead of the in-memory store:

### Dev + Production Tools

| Tool | Purpose |
|------|---------|
| `rails_markup_get_all_pending` | All pending annotations (proxies to dev DB when configured) |
| `rails_markup_get_pending` | Pending for one session |
| `rails_markup_watch_annotations` | Block until new annotations arrive |
| `rails_markup_acknowledge` | Mark annotation as seen |
| `rails_markup_resolve` | Mark resolved with summary |
| `rails_markup_dismiss` | Dismiss with reason |
| `rails_markup_reply` | Add reply to annotation thread |

### Production-specific Tools

For fetching from a separate production environment:

| Tool | Purpose |
|------|---------|
| `rails_markup_fetch_production` | Fetch pending from production (uses `RAILS_MARKUP_PROD_URL`) |
| `rails_markup_resolve_production` | Resolve a production annotation |
| `rails_markup_dismiss_production` | Dismiss a production annotation |
| `rails_markup_reply_production` | Reply to a production annotation |

## Dashboard

Visit your mount path (default `/admin/annotations`) to see all annotations with:

- Status filters (pending, acknowledged, resolved, dismissed)
- Bulk dismiss
- Thread replies
- Element selectors and CSS paths

## Architecture

```
Browser Toolbar                    AI Agent (Claude Code, Cursor)
    |                                    |
    | Same-origin API                    | MCP (stdio JSON-RPC)
    | (POST /admin/annotations/api/*)    | or CLI (bin/markup fetch)
    v                                    v
+----------------------------------------------------------+
|                  Rails Engine                             |
|                                                          |
|  Toolbar     →  Annotations    →  Dashboard              |
|  (Stimulus)     (ActiveRecord)    (/admin/annotations)   |
|                       ↑                                  |
|              External API (/external/*)                   |
|              (token-authenticated, used by MCP)           |
+----------------------------------------------------------+
```

- **Database-backed** — annotations persist across server restarts
- **Rails engine** — mounts into your app, inherits your auth
- **MCP proxy** — when `RAILS_MARKUP_DEV_URL` is set, MCP tools query your Rails DB directly

## Annotation Data

Each annotation includes:

- **CSS selector** — `div#hero.max-w-xl`
- **CSS path** — `body > main > div:nth-of-type(2) > div#hero`
- **Bounding box** — `{ top, left, width, height }`
- **Nearby text** — first 80 chars of the element's text content
- **Selected text** — if you highlighted text before clicking
- **Intent** — `fix`, `change`, `question`, or `approve`
- **Severity** — `suggestion`, `important`, or `blocking`

## Development

```bash
git clone https://github.com/inventlist/rails-markup
cd rails-markup && bundle install
bundle exec ruby -Ilib:test test/generators/install_generator_test.rb test/generators/uninstall_generator_test.rb
```

## License

MIT. See [LICENSE](LICENSE).

# Rails Markup

Point-and-click annotation tool for AI agents. Annotate your web app in the browser, and your AI agent reads and acts on your feedback via MCP.

## How it works

1. **Start the server** — `rails-markup server` runs an HTTP server (port 4747) and MCP server (stdio)
2. **Open your app** — The annotation toolbar appears as a floating button
3. **Click any element** — Hover to highlight, click to annotate, describe what needs to change
4. **Agent reads it** — Your AI calls `rails_markup_get_all_pending` via MCP
5. **Agent fixes it** — The agent resolves the annotation, your browser updates via SSE

## Install

### As a gem

```bash
gem install rails-markup
```

Or add to your Gemfile:

```ruby
gem "rails-markup", group: :development
```

### From source

```bash
git clone https://github.com/inventlist/rails-markup
cd rails-markup && bundle install
```

## Quick Start

### 1. Start the server

```bash
rails-markup server
# [rails-markup] HTTP server listening on port 4747
# [rails-markup] MCP server listening on stdio
```

Or with a custom port:

```bash
rails-markup server --port 8080
```

### 2. Add the toolbar to your app

**Rails** — add to your layout:

```erb
<%%= render "shared/annotation_toolbar" if Rails.env.development? %>
```

Copy the Stimulus controller and toolbar partial from this repo into your app:
- `app/javascript/controllers/annotate_controller.js`
- `app/views/shared/_annotation_toolbar.html.erb`

**Other frameworks** — use the HTTP API directly (see below).

### 3. Configure your AI agent

Add to `.mcp.json` (Claude Code, Cursor, or any MCP client):

```json
{
  "mcpServers": {
    "rails-markup": {
      "command": "rails-markup",
      "args": ["mcp"]
    }
  }
}
```

If using Bundler:

```json
{
  "mcpServers": {
    "rails-markup": {
      "command": "bundle",
      "args": ["exec", "rails-markup", "mcp"]
    }
  }
}
```

### 4. Annotate and fix

Click the floating button, click any element, type your feedback. The agent picks it up automatically.

### 5. (Optional) Add to Procfile

If your project uses `Procfile.dev` or `foreman`:

```
markup: rails-markup server
```

Now `bin/dev` starts the annotation server alongside your app.

## CLI Reference

```bash
rails-markup server              # HTTP on :4747 + MCP on stdio
rails-markup server --port 8080  # Custom port
rails-markup mcp                 # MCP only (no HTTP server)
rails-markup --help              # Show help
```

## MCP Tools

### Local Development (9 tools)

| Tool | Purpose |
|------|---------|
| `rails_markup_list_sessions` | List active annotation sessions |
| `rails_markup_get_session` | Get session with all annotations |
| `rails_markup_get_pending` | Pending annotations for one session |
| `rails_markup_get_all_pending` | All pending across all sessions |
| `rails_markup_watch_annotations` | Block until new annotations arrive |
| `rails_markup_acknowledge` | Mark annotation as seen |
| `rails_markup_resolve` | Mark resolved (pushes SSE to browser) |
| `rails_markup_dismiss` | Dismiss with reason (pushes SSE) |
| `rails_markup_reply` | Add reply to annotation thread (pushes SSE) |

### Production Feedback (4 tools)

For apps that persist annotations in their database (e.g., admin feedback on live sites):

| Tool | Purpose |
|------|---------|
| `rails_markup_fetch_production` | Fetch pending annotations from your production app |
| `rails_markup_resolve_production` | Resolve a production annotation |
| `rails_markup_dismiss_production` | Dismiss a production annotation |
| `rails_markup_reply_production` | Reply to a production annotation |

Production tools require env vars:

```json
{
  "mcpServers": {
    "rails-markup": {
      "command": "rails-markup",
      "args": ["mcp"],
      "env": {
        "RAILS_MARKUP_PROD_URL": "https://yourapp.com",
        "RAILS_MARKUP_PROD_TOKEN": "your-internal-api-token"
      }
    }
  }
}
```

Your app needs to implement the annotation API endpoints. See **Production Setup** below.

## HTTP API

| Method | Endpoint | Purpose |
|--------|----------|---------|
| `GET` | `/health` | Health check (`{"ok":true}`) |
| `POST` | `/sessions` | Create annotation session |
| `GET` | `/sessions` | List all sessions |
| `GET` | `/sessions/:id` | Get session with annotations |
| `POST` | `/sessions/:id/annotations` | Create annotation |
| `GET` | `/sessions/:id/events` | SSE event stream |
| `GET` | `/pending` | All pending annotations |
| `POST` | `/annotations/:id/resolve` | Resolve annotation |
| `POST` | `/annotations/:id/dismiss` | Dismiss annotation |
| `POST` | `/annotations/:id/acknowledge` | Acknowledge annotation |
| `POST` | `/annotations/:id/reply` | Reply to annotation |

## Architecture

```
Browser (Stimulus)              AI Agent (Claude Code, Cursor)
    |                                    |
    | HTTP (port 4747)                   | stdio (JSON-RPC)
    v                                    v
+----------------------------------------------------+
|              rails-markup server                    |
|                                                     |
|  CorsServlet  <->  In-Memory Store  <->  MCP Server |
|  (WEBrick,         (sessions,           (13 tools,  |
|   REST + SSE)       annotations,         JSON-RPC    |
|                     EventBus)            stdio)      |
+----------------------------------------------------+
         ^                                    |
         |          HttpStoreProxy            |
         +-------- (fallback when port -------+
                    is already taken)
```

- **No database** — local annotations are ephemeral (one coding session)
- **Single process** — HTTP + MCP share one store via EventBus
- **Pure Ruby** — WEBrick for HTTP, stdlib for everything else
- **Port resilience** — If port 4747 is taken, MCP proxies to the existing server via `HttpStoreProxy`
- **CORS** — Custom `CorsServlet` handles preflight for cross-origin browser requests

## Annotation Data

Each annotation includes:

- **CSS selector** — `div#hero.max-w-xl`
- **CSS path** — `body > main > div:nth-of-type(2) > div#hero`
- **Bounding box** — `{ top, left, width, height }`
- **Nearby text** — First 80 chars of the element's text content
- **Selected text** — If you highlighted text before clicking
- **Intent** — `fix`, `change`, `question`, or `approve`
- **Severity** — `suggestion`, `important`, or `blocking`

## Production Setup (Optional)

To persist annotations in your database and allow admin feedback on live pages:

### 1. Create an `Annotation` model

```ruby
# db/migrate/..._create_annotations.rb
create_table :annotations do |t|
  t.references :user, null: false, foreign_key: true
  t.string :page_url, null: false
  t.jsonb :target, default: {}
  t.text :content, null: false
  t.string :intent, null: false, default: "change"
  t.string :severity, null: false, default: "suggestion"
  t.string :status, null: false, default: "pending"
  t.text :selected_text
  t.jsonb :metadata, default: {}
  t.jsonb :thread, default: []
  t.timestamps
end
```

### 2. Implement the API endpoints

The production MCP tools expect these endpoints on your app:

| Method | Path | Purpose |
|--------|------|---------|
| `GET` | `/internal/annotations/pending` | Return pending annotations as JSON |
| `PATCH` | `/internal/annotations/:id/acknowledge` | Mark acknowledged |
| `PATCH` | `/internal/annotations/:id/resolve` | Resolve with summary |
| `PATCH` | `/internal/annotations/:id/dismiss` | Dismiss with reason |
| `PATCH` | `/internal/annotations/:id/reply` | Reply with message |

Authenticate with a Bearer token in the `Authorization` header.

### 3. Show toolbar for admins

```erb
<%% if Rails.env.development? || current_user&.admin? %>
  <%%= render "shared/annotation_toolbar" %>
<%% end %>
```

The toolbar auto-detects dev vs production mode and switches endpoints accordingly.

## Framework Integration

### Rails (Stimulus)

Ships with `annotate_controller.js` and `_annotation_toolbar.html.erb`. Drop into any Rails 7+ app.

### Other Frameworks

The HTTP API is framework-agnostic. Any JavaScript client can:

1. `POST /sessions` to create a session
2. `POST /sessions/:id/annotations` to submit annotations
3. `GET /sessions/:id/events` to receive SSE updates

## Development

```bash
cd packages/rails-markup  # or wherever you cloned it
bundle install
bundle exec rake test
```

## License

MIT. See [LICENSE](LICENSE).

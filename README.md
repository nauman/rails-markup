# Rails Markup

Point-and-click annotation tool for AI agents. Annotate your Rails views in the browser, and your AI agent reads and acts on your feedback via MCP.

## How it works

1. **Start the server** — `rails-markup server` runs an HTTP server (port 4747) and MCP server (stdio)
2. **Open your app** — The annotation toolbar appears as a floating button in development
3. **Click any element** — Hover to highlight, click to annotate, describe what needs to change
4. **Agent reads it** — Your AI calls `rails_markup_get_all_pending` via MCP
5. **Agent fixes it** — The agent resolves the annotation, your browser updates via SSE

## Install

```bash
gem install rails-markup
```

## Quick Start

### 1. Start the server

```bash
rails-markup server
# [rails-markup] HTTP server listening on port 4747
# [rails-markup] MCP server listening on stdio
```

### 2. Add the toolbar to your Rails layout

```erb
<%%= render "shared/annotation_toolbar" if Rails.env.development? %>
```

### 3. Configure your AI agent

**Claude Code** (`~/.claude/claude_code_config.json`):

```json
{
  "mcpServers": {
    "rails-markup": {
      "command": "rails-markup",
      "args": ["server"]
    }
  }
}
```

**Cursor** (`.cursor/mcp.json`):

```json
{
  "mcpServers": {
    "rails-markup": {
      "command": "rails-markup",
      "args": ["server"]
    }
  }
}
```

### 4. Annotate and fix

Click the floating button, click any element, type your feedback. The agent picks it up automatically.

## CLI Reference

```bash
rails-markup server              # HTTP on :4747 + MCP on stdio
rails-markup server --port 8080  # Custom port
rails-markup mcp                 # MCP only (no HTTP server)
rails-markup --help              # Show help
```

## HTTP API

| Method | Endpoint | Purpose |
|--------|----------|---------|
| `GET` | `/health` | Health check (`{"ok":true}`) |
| `POST` | `/sessions` | Create annotation session |
| `GET` | `/sessions/:id` | Get session with annotations |
| `POST` | `/sessions/:id/annotations` | Create annotation |
| `GET` | `/sessions/:id/events` | SSE event stream |
| `GET` | `/pending` | All pending annotations |

## MCP Tools (9 total)

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

## Architecture

```
Browser (Stimulus)              AI Agent (Claude Code, Cursor)
    |                                    |
    | HTTP (port 4747)                   | stdio (JSON-RPC)
    v                                    v
+----------------------------------------------------+
|              rails-markup server                    |
|                                                     |
|  HTTP Server  <->  In-Memory Store  <->  MCP Server |
|  (WEBrick,         (sessions,           (9 tools,   |
|   REST + SSE)       annotations,         JSON-RPC    |
|                     EventBus)            stdio)      |
+----------------------------------------------------+
```

- **No database** — annotations are ephemeral (one coding session)
- **Single process** — HTTP + MCP share one store via EventBus
- **Pure Ruby** — WEBrick for HTTP, stdlib for everything else

## Annotation Data

Each annotation includes:

- **CSS selector** — `div#hero.max-w-xl`
- **CSS path** — `body > main > div:nth-of-type(2) > div#hero`
- **Bounding box** — `{ top, left, width, height }`
- **Nearby text** — First 80 chars of the element's text content
- **Selected text** — If you highlighted text before clicking
- **Intent** — `fix`, `change`, `question`, or `approve`
- **Severity** — `suggestion`, `important`, or `blocking`

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
cd packages/rails-markup
bundle install
bundle exec rake test
```

## License

MIT. See [LICENSE](LICENSE).

# frozen_string_literal: true

require "thor"
require "lipgloss"
require "set"
require_relative "../rails_markup"
require_relative "mcp_config"

module RailsMarkup
  class Cli < Thor
    require_relative "cli/initializer_writer"
    require_relative "cli/setup_wizard"
    # ── Lipgloss styles ────────────────────────────────────────
    HEADER_STYLE = Lipgloss::Style.new.bold(true).foreground("#FFFFFF").background("#5C4AE4").padding(0, 1)
    ODD_STYLE    = Lipgloss::Style.new.foreground("#E2E2E2").padding(0, 1)
    EVEN_STYLE   = Lipgloss::Style.new.foreground("#A0A0A0").padding(0, 1)
    MASKED_STYLE = Lipgloss::Style.new.foreground("#6B7280").padding(0, 1)
    LABEL_STYLE  = Lipgloss::Style.new.bold(true).foreground("#FFFFFF")
    HINT_STYLE   = Lipgloss::Style.new.foreground("#6B7280")
    SUCCESS_STYLE = Lipgloss::Style.new.bold(true).foreground("#22C55E")
    ERROR_STYLE   = Lipgloss::Style.new.bold(true).foreground("#EF4444")

    desc "server", "Start HTTP + MCP server"
    long_desc <<-DESC
      Start the combined HTTP annotation server and MCP stdio bridge.

      The HTTP server serves the annotation toolbar and API endpoints.
      The MCP bridge lets AI editors communicate via JSON-RPC over stdio.

      Examples:

        bin/markup server               # default port 4747

        bin/markup server --port 5000   # custom port
    DESC
    method_option :port, type: :numeric, default: 4747, desc: "HTTP server port"
    def server
      srv = RailsMarkup::Server.new(port: options[:port])
      srv.start
    end

    desc "init", "Interactive setup wizard"
    long_desc <<-DESC
      Launch the interactive TUI setup wizard.

      Walks through toolbar accent, position, size, screenshots,
      production URL, and MCP scope (local/global/codex).
      Writes the Rails initializer and MCP config on confirm.

      Requires a terminal with arrow key support.
    DESC
    def init
      wizard = Cli::SetupWizard.new(dir: Dir.pwd)
      Bubbletea.run(wizard)
      if wizard.completed
        say ""
        say "Setup complete!", :green
      else
        say ""
        say "Setup cancelled.", :yellow
      end
    end

    desc "mcp", "Start MCP-only server (stdio)"
    long_desc <<-DESC
      Start the MCP server in stdio-only mode (no HTTP server).

      This is what AI editors (Claude Code, Codex CLI, Cursor) invoke
      via .mcp.json or global config. Communicates over stdin/stdout
      using the JSON-RPC MCP protocol.

      You rarely need to run this manually — it's called by the editor.
    DESC
    method_option :port, type: :numeric, default: 4747, desc: "HTTP server port to proxy to"
    def mcp
      srv = RailsMarkup::Server.new(port: options[:port], mcp_only: true)
      srv.start
    end

    desc "configure", "Set MCP env vars (local, global, or codex)"
    long_desc <<-DESC
      Write environment variables to the MCP config file for this project
      or globally for all projects.

      Scope flags:

        (default)  Write to .mcp.json in the current directory

        --global   Write to ~/.claude/settings.json (Claude Code)

        --codex    Write to ~/.codex/config.toml (OpenAI Codex CLI)

      Examples:

        bin/markup configure --dev-url http://localhost:3000

        bin/markup configure --prod-url URL --prod-token TOKEN

        bin/markup configure --prod-url URL --global

        bin/markup configure --prod-url URL --codex
    DESC
    method_option :prod_url,   type: :string, desc: "Production URL (RAILS_MARKUP_PROD_URL)"
    method_option :prod_token, type: :string, desc: "Production API token (RAILS_MARKUP_PROD_TOKEN)"
    method_option :dev_url,    type: :string, desc: "Dev URL (RAILS_MARKUP_DEV_URL)"
    method_option :mount_path, type: :string, desc: "Engine mount path (RAILS_MARKUP_MOUNT_PATH)"
    method_option :global, type: :boolean, default: false, desc: "Write to ~/.claude/settings.json"
    method_option :codex,  type: :boolean, default: false, desc: "Write to ~/.codex/config.toml"
    def configure
      env_updates = McpConfig::ENV_KEYS.each_with_object({}) do |(opt, env_key), hash|
        hash[env_key] = options[opt] if options[opt]
      end

      if env_updates.empty?
        say "No options provided. Usage:", :yellow
        say ""
        say "  bin/markup configure --dev-url http://localhost:3000"
        say "  bin/markup configure --prod-url URL --prod-token TOKEN"
        say "  bin/markup configure --prod-url URL --global     # Claude Code global"
        say "  bin/markup configure --prod-url URL --codex      # Codex CLI global"
        say ""
        say "  Dev needs only a URL (no token). Production requires both."
        say ""
        say "  Or run: bin/markup setup-production --url=https://yourapp.com"
        say ""
        return
      end

      config = McpConfig.new(scope: resolve_scope)
      config.update_env(env_updates)
      $stdout.puts "#{LABEL_STYLE.render("Updated #{config.scope_label}")}  #{HINT_STYLE.render("(#{config.path})")}"
      $stdout.puts env_table(config.display_env, label: config.scope_label)
    end

    desc "status", "Show MCP config across all scopes"
    long_desc <<-DESC
      Display the current MCP configuration across all scopes.

      Checks .mcp.json (local), ~/.claude/settings.json (Claude Code),
      and ~/.codex/config.toml (Codex CLI). Tokens are masked.
    DESC
    def status
      found = false

      McpConfig::SCOPES.each do |scope|
        config = McpConfig.new(scope: scope)
        next unless config.exist?

        env = config.display_env
        next if env.empty?

        found = true
        say ""
        $stdout.puts env_table(env, label: config.scope_label)
      end

      unless found
        say ""
        say "No MCP config found. Run:", :yellow
        say "  rails-markup configure --prod-url URL --prod-token TOKEN"
        say "  rails-markup configure --prod-url URL --global   # Claude Code global"
        say "  rails-markup configure --prod-url URL --codex    # Codex CLI global"
      end
      say ""
    end

    # ── Unified commands (match MCP tool verbs) ──────────────

    desc "sessions", "List active annotation sessions (MCP only)"
    def sessions
      say "Sessions are only available via MCP tools (in-memory store).", :yellow
      say ""
      say "  Use the rails_markup_sessions MCP tool in your AI editor."
      say "  The CLI talks to the Rails API which has database-backed annotations,"
      say "  not session-based ones."
      say ""
      say "  To view pending annotations: bin/markup pending"
    end

    desc "session ID", "Get a session with annotations (MCP only)"
    def session(id = nil)
      say "Sessions are only available via MCP tools (in-memory store).", :yellow
      say ""
      say "  Use the rails_markup_session MCP tool in your AI editor."
      say ""
      say "  To view pending annotations: bin/markup pending"
    end

    desc "watch", "Watch for new annotations (polls pending)"
    long_desc <<-DESC
      Poll for new annotations and print them as they arrive.
      Press Ctrl+C to stop.

      Examples:

        bin/markup watch                      # local dev, 5s interval

        bin/markup watch --production         # production

        bin/markup watch --interval 2         # poll every 2s
    DESC
    method_option :production, type: :boolean, default: false, desc: "Watch production"
    method_option :url, type: :string, desc: "Override base URL"
    method_option :token, type: :string, desc: "Override API token"
    method_option :mount_path, type: :string, desc: "Engine mount path"
    method_option :interval, type: :numeric, default: 5, desc: "Poll interval in seconds"
    def watch
      env = resolve_env(options[:production])
      return unless env

      env_label = options[:production] ? "Production" : "Development"
      interval = [options[:interval], 1].max

      $stdout.puts ""
      $stdout.puts "#{LABEL_STYLE.render(" Watching #{env_label} ")} #{HINT_STYLE.render(env[:base_url])}"
      $stdout.puts "#{HINT_STYLE.render("  Polling every #{interval}s. Press Ctrl+C to stop.")}"
      $stdout.puts ""

      seen_ids = Set.new
      loop do
        annotations = fetch_pending_from(env)
        break unless annotations

        new_annotations = annotations.reject { |ann| seen_ids.include?(ann["id"]) }
        if new_annotations.any?
          new_annotations.each do |ann|
            seen_ids.add(ann["id"])
            render_annotation(ann)
          end
          $stdout.puts "#{HINT_STYLE.render("  #{seen_ids.size} total seen, #{annotations.size} pending")}"
          $stdout.puts ""
        end

        sleep interval
      rescue Interrupt
        say ""
        say "Stopped watching.", :yellow
        break
      end
    end

    desc "pending", "Fetch pending annotations"
    long_desc <<-DESC
      Fetch all pending (unresolved) annotations from the Rails API.

      Examples:

        bin/markup pending                    # local dev

        bin/markup pending --production       # production
    DESC
    method_option :production, type: :boolean, default: false, desc: "Fetch from production"
    method_option :url, type: :string, desc: "Override base URL"
    method_option :token, type: :string, desc: "Override API token"
    method_option :mount_path, type: :string, desc: "Engine mount path"
    def pending
      env = resolve_env(options[:production])
      return unless env

      annotations = fetch_pending_from(env)
      return unless annotations

      env_label = options[:production] ? "Production" : "Development"
      $stdout.puts ""
      $stdout.puts "#{LABEL_STYLE.render(" #{env_label} ")} #{HINT_STYLE.render(env[:base_url])}"
      $stdout.puts ""

      if annotations.empty?
        say "  No pending annotations.", :yellow
        say ""
        return
      end

      $stdout.puts annotation_table(annotations)
      say ""
      annotations.each { |ann| render_annotation(ann) }
    end

    desc "resolve-all", "Resolve all pending annotations"
    long_desc <<-DESC
      Batch-resolve every pending annotation.

      Examples:

        bin/markup resolve-all --summary "Shipped in v2.1"

        bin/markup resolve-all --production --summary "Done"
    DESC
    method_option :summary, type: :string, desc: "Summary applied to all"
    method_option :production, type: :boolean, default: false, desc: "Target production"
    def resolve_all
      env = resolve_env(options[:production])
      return unless env

      annotations = fetch_pending_from(env)
      return unless annotations

      if annotations.empty?
        say "No pending annotations.", :yellow
        return
      end

      resolved = 0
      annotations.each do |ann|
        result = patch_annotation(env, ann["id"], "resolve", summary: options[:summary])
        if result
          $stdout.puts "#{SUCCESS_STYLE.render("Resolved")} ##{ann["id"]}  #{HINT_STYLE.render(ann["content"].to_s[0, 50])}"
          resolved += 1
        else
          $stdout.puts "#{ERROR_STYLE.render("Failed")}  ##{ann["id"]}"
        end
      end

      say ""
      say "#{resolved}/#{annotations.size} annotations resolved.", :green
    end

    desc "resolve ID", "Resolve an annotation with a summary"
    long_desc <<-DESC
      Mark a single annotation as resolved.

      Examples:

        bin/markup resolve 42 --summary "Fixed padding"

        bin/markup resolve 42 --production
    DESC
    method_option :summary, type: :string, desc: "Summary of how it was resolved"
    method_option :production, type: :boolean, default: false, desc: "Target production"
    def resolve(id = nil)
      return say("#{ERROR_STYLE.render("Error:")} annotation ID is required") unless id

      env = resolve_env(options[:production])
      return unless env

      result = patch_annotation(env, id, "resolve", summary: options[:summary])
      return unless result

      $stdout.puts "#{SUCCESS_STYLE.render("Resolved")} ##{id}"
    end

    desc "dismiss ID", "Dismiss an annotation with a reason"
    long_desc <<-DESC
      Dismiss an annotation (won't fix, not applicable, etc).

      Examples:

        bin/markup dismiss 42 --reason "By design"

        bin/markup dismiss 42 --production --reason "Duplicate"
    DESC
    method_option :reason, type: :string, desc: "Reason for dismissing"
    method_option :production, type: :boolean, default: false, desc: "Target production"
    def dismiss(id = nil)
      return say("#{ERROR_STYLE.render("Error:")} annotation ID is required") unless id

      env = resolve_env(options[:production])
      return unless env

      result = patch_annotation(env, id, "dismiss", reason: options[:reason])
      return unless result

      $stdout.puts "#{SUCCESS_STYLE.render("Dismissed")} ##{id}"
    end

    desc "reply ID MESSAGE", "Reply to an annotation thread"
    long_desc <<-DESC
      Add a reply to an annotation's discussion thread.

      Examples:

        bin/markup reply 42 "Fixed in commit abc123"

        bin/markup reply 42 "Deployed" --production
    DESC
    method_option :production, type: :boolean, default: false, desc: "Target production"
    def reply(id = nil, message = nil)
      return say("#{ERROR_STYLE.render("Error:")} annotation ID is required") unless id
      return say("#{ERROR_STYLE.render("Error:")} message is required") unless message

      env = resolve_env(options[:production])
      return unless env

      result = patch_annotation(env, id, "reply", message: message)
      return unless result

      $stdout.puts "#{SUCCESS_STYLE.render("Reply sent")} to ##{id}"
    end

    desc "acknowledge ID", "Mark an annotation as acknowledged"
    long_desc <<-DESC
      Mark an annotation as seen/acknowledged without resolving it.

      Examples:

        bin/markup acknowledge 42

        bin/markup acknowledge 42 --production
    DESC
    method_option :production, type: :boolean, default: false, desc: "Target production"
    def acknowledge(id = nil)
      return say("#{ERROR_STYLE.render("Error:")} annotation ID is required") unless id

      env = resolve_env(options[:production])
      return unless env

      result = patch_annotation(env, id, "acknowledge")
      return unless result

      $stdout.puts "#{SUCCESS_STYLE.render("Acknowledged")} ##{id}"
    end

    # ── Shorthand aliases ─────────────────────────────────────

    desc "fetch [ENVIRONMENT]", "Fetch pending annotations (default: local dev)"
    long_desc <<-DESC
      Fetch pending annotations from local dev or production.

      Examples:
        bin/markup fetch              # local dev
        bin/markup fetch production   # production
        bin/markup fetch -e production  # also production
    DESC
    method_option :production, type: :boolean, default: false, desc: "Fetch from production"
    method_option :environment, type: :string, aliases: "-e", enum: %w[dev production],
      desc: "Environment to fetch from"
    method_option :url, type: :string, desc: "Override base URL"
    method_option :token, type: :string, desc: "Override API token"
    method_option :mount_path, type: :string, desc: "Engine mount path (default: /admin/annotations)"
    def fetch(env_arg = nil)
      production = env_arg == "production" || options[:production] || options[:environment] == "production"
      env = resolve_env(production)
      return unless env

      annotations = fetch_pending_from(env)
      return unless annotations

      env_label = production ? "Production" : "Development"
      $stdout.puts ""
      $stdout.puts "#{LABEL_STYLE.render(" #{env_label} ")} #{HINT_STYLE.render(env[:base_url])}"
      $stdout.puts ""

      if annotations.empty?
        say "  No pending annotations.", :yellow
        say ""
        return
      end

      $stdout.puts annotation_table(annotations)
      say ""
      annotations.each { |ann| render_annotation(ann) }
    end

    desc "setup-production", "Generate a token and configure production access"
    long_desc <<-DESC
      Generate a secure API token, save it to MCP config, and print
      instructions for adding it to your Rails credentials.

      Examples:

        bin/markup setup-production --url=https://yourapp.com

        bin/markup setup-production --url=https://yourapp.com --global

        bin/markup setup-production --url=https://yourapp.com --codex
    DESC
    method_option :url, type: :string, desc: "Production URL (e.g. https://yourapp.com)"
    method_option :global, type: :boolean, default: false, desc: "Write to ~/.claude/settings.json"
    method_option :codex,  type: :boolean, default: false, desc: "Write to ~/.codex/config.toml"
    def setup_production
      require "securerandom"

      prod_url = options[:url]
      unless prod_url
        say "Usage: bin/markup setup-production --url=https://yourapp.com", :red
        return
      end

      token = SecureRandom.hex(24)

      config = McpConfig.new(scope: resolve_scope)
      config.update_env({
        "RAILS_MARKUP_PROD_URL" => prod_url,
        "RAILS_MARKUP_PROD_TOKEN" => token
      })

      say ""
      say "Production token generated!", :green
      say ""
      say "Token: #{token}"
      say ""
      say "Saved to #{config.scope_label} — CLI and MCP tools are ready."
      say ""
      say "Now add the same token to your Rails app:"
      say ""
      say "  Option A: Rails credentials (recommended)"
      say "    rails credentials:edit"
      say "    # Add:"
      say "    # rails_markup:"
      say "    #   api_token: #{token}"
      say ""
      say "  Option B: Environment variable"
      say "    RAILS_MARKUP_API_TOKEN=#{token}"
      say ""
      say "Then in config/initializers/rails_markup.rb:"
      say '  config.api_token = Rails.application.credentials.dig(:rails_markup, :api_token)'
      say "  # or"
      say '  config.api_token = ENV["RAILS_MARKUP_API_TOKEN"]'
      say ""
      say "Deploy, then verify:"
      say "  bin/markup pending --production"
      say ""
    end

    desc "man", "Full command reference with examples"
    def man
      require_relative "version"
      $stdout.puts render_man_page
    end

    desc "version", "Print version"
    def version
      require_relative "version"
      say "rails-markup #{RailsMarkup::VERSION}"
    end

    def self.exit_on_failure?
      true
    end

    private

    def render_man_page
      require_relative "version"
      sections = []

      sections << HEADER_STYLE.render(" RAILS-MARKUP(1) — v#{RailsMarkup::VERSION} ")
      sections << ""
      sections << "  Point-and-click annotation tool for AI agents."
      sections << "  Annotate Rails views in the browser; AI editors read and act on your feedback."
      sections << ""

      sections << LABEL_STYLE.render(" GETTING STARTED ")
      sections << ""
      sections << "  #{HINT_STYLE.render("# 1. Add to Gemfile")}"
      sections << '  gem "rails-markup"'
      sections << ""
      sections << "  #{HINT_STYLE.render("# 2. Run install generator")}"
      sections << "  rails generate rails_markup:install"
      sections << "  rails db:migrate"
      sections << ""
      sections << "  #{HINT_STYLE.render("# 3. Interactive setup (toolbar + MCP config)")}"
      sections << "  bin/markup init"
      sections << ""
      sections << "  #{HINT_STYLE.render("# 4. Or configure manually")}"
      sections << "  bin/markup configure --dev-url http://localhost:3000"
      sections << "  bin/markup setup-production --url https://yourapp.com"
      sections << ""

      sections << LABEL_STYLE.render(" SETUP ")
      sections << ""
      sections << "  init                      Interactive TUI wizard"
      sections << "  configure [OPTIONS]       Set MCP env vars"
      sections << "    --prod-url URL            Production URL"
      sections << "    --prod-token TOKEN        Production API token"
      sections << "    --dev-url URL             Development URL"
      sections << "    --mount-path PATH         Engine mount path"
      sections << "    --global                  Write to ~/.claude/settings.json"
      sections << "    --codex                   Write to ~/.codex/config.toml"
      sections << "  setup-production --url URL Generate token + configure production"
      sections << "    --global / --codex        Same scope flags as configure"
      sections << "  status                    Show config across all scopes"
      sections << ""

      sections << LABEL_STYLE.render(" SERVERS ")
      sections << ""
      sections << "  server [--port N]         Start HTTP + MCP server (default: 4747)"
      sections << "  mcp    [--port N]         Start MCP-only server (stdio, for editors)"
      sections << ""

      sections << LABEL_STYLE.render(" ANNOTATIONS ")
      sections << ""
      sections << "  pending [--production]    Fetch pending annotations"
      sections << "  fetch [ENV]               Alias for pending (accepts 'production' arg)"
      sections << "  watch [--production]      Poll and print new annotations (Ctrl+C to stop)"
      sections << "    --interval N              Seconds between polls (default: 5)"
      sections << "  resolve ID [--summary S]  Resolve an annotation"
      sections << "  resolve-all [--summary S] Batch-resolve all pending"
      sections << "  dismiss ID [--reason R]   Dismiss an annotation"
      sections << "  reply ID MESSAGE          Reply to an annotation thread"
      sections << "  acknowledge ID            Mark as seen"
      sections << ""
      sections << "  #{HINT_STYLE.render("All annotation commands accept --production to target prod.")}"
      sections << ""

      sections << LABEL_STYLE.render(" MCP CONFIG SCOPES ")
      sections << ""
      sections << "  local    .mcp.json                     This project only"
      sections << "  global   ~/.claude/settings.json       Claude Code (all projects)"
      sections << "  codex    ~/.codex/config.toml          Codex CLI (all projects)"
      sections << ""
      sections << "  #{HINT_STYLE.render("Commands fall back through local → global → codex when resolving env.")}"
      sections << ""

      sections << LABEL_STYLE.render(" QUICK RECIPES ")
      sections << ""
      sections << "  #{HINT_STYLE.render("# Dev setup")}"
      sections << "  bin/markup configure --dev-url http://localhost:3000"
      sections << ""
      sections << "  #{HINT_STYLE.render("# Production setup (writes to global Claude Code config)")}"
      sections << "  bin/markup setup-production --url https://myapp.com --global"
      sections << ""
      sections << "  #{HINT_STYLE.render("# Watch for annotations in real-time")}"
      sections << "  bin/markup watch --production --interval 2"
      sections << ""
      sections << "  #{HINT_STYLE.render("# Resolve everything after a deploy")}"
      sections << "  bin/markup resolve-all --production --summary \"Shipped in v2.1\""
      sections << ""

      sections << LABEL_STYLE.render(" INFO ")
      sections << ""
      sections << "  man                       This reference page"
      sections << "  version                   Print version"
      sections << "  help [COMMAND]            Thor help for a specific command"
      sections << ""

      sections.join("\n")
    end

    # ── Environment resolution ────────────────────────────────

    def resolve_scope
      return "global" if options[:global]
      return "codex"  if options[:codex]

      "local"
    end

    # Check local first, then fall back to global/codex configs.
    def resolve_mcp_env
      McpConfig::SCOPES.each do |scope|
        config = McpConfig.new(scope: scope)
        next unless config.exist?

        env = config.raw_env
        return env unless env.empty?
      end

      {}
    end

    def resolve_env(production)
      mcp_env = resolve_mcp_env

      if production
        base_url = options[:url] || mcp_env["RAILS_MARKUP_PROD_URL"]
        token = options[:token] || mcp_env["RAILS_MARKUP_PROD_TOKEN"]
        mount = options[:mount_path] || mcp_env["RAILS_MARKUP_MOUNT_PATH"] || "/admin/annotations"

        unless base_url
          say "No production URL. Set it via:", :red
          say "  bin/markup configure --prod-url URL"
          return nil
        end

        unless token
          say "No production token configured.", :red
          say "  bin/markup configure --prod-token TOKEN"
          return nil
        end

        { base_url: base_url, token: token, mount_path: mount }
      else
        base_url = options[:url] || mcp_env["RAILS_MARKUP_DEV_URL"]
        token = options[:token] || mcp_env["RAILS_MARKUP_DEV_TOKEN"]
        mount = options[:mount_path] || mcp_env["RAILS_MARKUP_MOUNT_PATH"] || "/admin/annotations"

        unless base_url
          say "No dev URL. Set it via:", :red
          say "  bin/markup configure --dev-url URL"
          return nil
        end

        { base_url: base_url, token: token, mount_path: mount }
      end
    end

    def api_base(env)
      "#{env[:base_url]}#{env[:mount_path]}/external"
    end

    # ── HTTP helpers ──────────────────────────────────────────

    def fetch_pending_from(env)
      require "net/http"
      require "uri"
      require "json"

      url = "#{api_base(env)}/pending"
      resp = http_get(url, token: env[:token])

      unless resp.is_a?(Net::HTTPSuccess)
        say "API error: #{resp.code} #{resp.body}", :red
        return nil
      end

      data = JSON.parse(resp.body)
      data["annotations"] || []
    rescue => e
      say "Connection error: #{e.message}", :red
      nil
    end

    def patch_annotation(env, id, action, **params)
      require "net/http"
      require "uri"
      require "json"

      url = "#{api_base(env)}/#{id}/#{action}"
      resp = http_patch(url, token: env[:token], params: params.compact)

      unless resp.is_a?(Net::HTTPSuccess)
        say "API error: #{resp.code} #{resp.body}", :red
        return nil
      end

      JSON.parse(resp.body)
    rescue => e
      say "Connection error: #{e.message}", :red
      nil
    end

    def http_get(url, token: nil)
      uri = URI.parse(url)
      req = Net::HTTP::Get.new(uri)
      req["Authorization"] = "Bearer #{token}" if token
      req["Accept"] = "application/json"
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = 10
      http.read_timeout = 15
      http.request(req)
    end

    def http_patch(url, token: nil, params: {})
      uri = URI.parse(url)
      req = Net::HTTP::Patch.new(uri)
      req["Authorization"] = "Bearer #{token}" if token
      req["Content-Type"] = "application/json"
      req["Accept"] = "application/json"
      req.body = params.to_json unless params.empty?
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = 10
      http.read_timeout = 15
      http.request(req)
    end

    # ── Rendering ─────────────────────────────────────────────

    def annotation_table(annotations)
      rows = annotations.map do |ann|
        page = URI.parse(ann["pageUrl"]).path rescue ann["pageUrl"]
        ["##{ann["id"]}", ann["intent"], ann["severity"], truncate(page, 30)]
      end

      Lipgloss::Table.new
        .headers(["ID", "Intent", "Severity", "Page"])
        .rows(rows)
        .border(:rounded)
        .style_func(rows: rows.size, columns: 4) do |row, _col|
          if row == Lipgloss::Table::HEADER_ROW
            HEADER_STYLE
          else
            row.odd? ? MASKED_STYLE : ODD_STYLE
          end
        end
        .render
    end

    def render_annotation(ann)
      target = ann["target"] || {}
      page = URI.parse(ann["pageUrl"]).path rescue ann["pageUrl"]
      nearby = target["nearbyText"]&.strip&.gsub(/\s+/, " ")&.slice(0, 80)

      say "─" * 60
      $stdout.puts "#{LABEL_STYLE.render(" ##{ann["id"]} ")} #{ann["intent"]} | #{ann["severity"]}  #{HINT_STYLE.render(page)}"
      say ""
      say "  #{ann["content"]}"
      say ""
      say "  Author:    #{ann["authorName"]}" if ann["authorName"]
      say "  CSS path:  #{target["cssPath"]}" if target["cssPath"]
      say "  Selector:  #{target["selector"]}" if target["selector"]
      say "  Text near: \"#{nearby}\"" if nearby
      say "  Selected:  \"#{ann["selectedText"]}\"" if ann["selectedText"]
      say "  Created:   #{ann["createdAt"]}"
      say ""
    end

    def env_table(env_hash, label: ".mcp.json")
      rows = env_hash.map { |k, v| [k, v] }
      table = Lipgloss::Table.new
        .headers(["Variable", "Value"])
        .rows(rows)
        .border(:rounded)
        .style_func(rows: rows.size, columns: 2) do |row, _col|
          if row == Lipgloss::Table::HEADER_ROW
            HEADER_STYLE
          else
            row.odd? ? MASKED_STYLE : ODD_STYLE
          end
        end
        .render

      title = LABEL_STYLE.render(" Rails Markup ")
      path = HINT_STYLE.render(label)
      "#{title} #{path}\n\n#{table}"
    end

    def truncate(str, limit)
      return str if str.length <= limit

      "#{str[0, limit - 3]}..."
    end
  end
end

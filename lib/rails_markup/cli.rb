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
    method_option :port, type: :numeric, default: 4747, desc: "HTTP server port"
    def server
      srv = RailsMarkup::Server.new(port: options[:port])
      srv.start
    end

    desc "init", "Interactive setup wizard"
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
    method_option :port, type: :numeric, default: 4747, desc: "HTTP server port to proxy to"
    def mcp
      srv = RailsMarkup::Server.new(port: options[:port], mcp_only: true)
      srv.start
    end

    desc "configure", "Set .mcp.json env vars for this project"
    method_option :prod_url,   type: :string, desc: "Production URL (RAILS_MARKUP_PROD_URL)"
    method_option :prod_token, type: :string, desc: "Production API token (RAILS_MARKUP_PROD_TOKEN)"
    method_option :dev_url,    type: :string, desc: "Dev URL (RAILS_MARKUP_DEV_URL)"
    method_option :mount_path, type: :string, desc: "Engine mount path (RAILS_MARKUP_MOUNT_PATH)"
    def configure
      env_updates = McpConfig::ENV_KEYS.each_with_object({}) do |(opt, env_key), hash|
        hash[env_key] = options[opt] if options[opt]
      end

      if env_updates.empty?
        say "No options provided. Usage:", :yellow
        say ""
        say "  bin/markup configure --dev-url http://localhost:3000"
        say "  bin/markup configure --prod-url URL --prod-token TOKEN"
        say ""
        say "  Dev needs only a URL (no token). Production requires both."
        say ""
        say "  Or run: bin/markup setup-production --url=https://yourapp.com"
        say ""
        return
      end

      config = McpConfig.new
      config.update_env(env_updates)
      $stdout.puts "#{LABEL_STYLE.render("Updated .mcp.json")}  #{HINT_STYLE.render("(#{Dir.pwd})")}"
      $stdout.puts env_table(config.display_env)
    end

    desc "status", "Show current .mcp.json config (tokens masked)"
    def status
      config = McpConfig.new
      unless config.exist?
        say "No .mcp.json found in #{Dir.pwd}", :yellow
        say "Run: rails-markup configure --prod-url URL --prod-token TOKEN"
        return
      end

      env = config.display_env
      say ""
      if env.empty?
        say "  (no env vars set for rails-markup)"
      else
        $stdout.puts env_table(env)
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

    desc "resolve ID", "Resolve an annotation with a summary"
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
    method_option :production, type: :boolean, default: false, desc: "Target production"
    def acknowledge(id = nil)
      return say("#{ERROR_STYLE.render("Error:")} annotation ID is required") unless id

      env = resolve_env(options[:production])
      return unless env

      result = patch_annotation(env, id, "acknowledge")
      return unless result

      $stdout.puts "#{SUCCESS_STYLE.render("Acknowledged")} ##{id}"
    end

    # ── Legacy aliases ───────────────────────────────────────

    desc "fetch", "Fetch pending annotations (use 'pending' instead)"
    method_option :env, type: :string, default: "dev", enum: %w[dev production],
      desc: "Which environment to fetch from"
    method_option :url, type: :string, desc: "Override base URL"
    method_option :token, type: :string, desc: "Override API token"
    method_option :mount_path, type: :string, desc: "Engine mount path (default: /admin/annotations)"
    def fetch
      production = options[:env] == "production"
      invoke :pending, [], production: production, url: options[:url], token: options[:token], mount_path: options[:mount_path]
    end

    desc "production", "Fetch pending annotations from production (use 'pending --production' instead)"
    def production
      invoke :pending, [], production: true
    end

    desc "setup-production", "Generate a token and configure production access"
    method_option :url, type: :string, desc: "Production URL (e.g. https://yourapp.com)"
    def setup_production
      require "securerandom"

      prod_url = options[:url]
      unless prod_url
        say "Usage: bin/markup setup-production --url=https://yourapp.com", :red
        return
      end

      token = SecureRandom.hex(24)

      # Save to .mcp.json
      config = McpConfig.new
      config.update_env({
        "RAILS_MARKUP_PROD_URL" => prod_url,
        "RAILS_MARKUP_PROD_TOKEN" => token
      })

      say ""
      say "Production token generated!", :green
      say ""
      say "Token: #{token}"
      say ""
      say "Saved to .mcp.json — CLI and MCP tools are ready."
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

    def self.exit_on_failure?
      true
    end

    private

    # ── Environment resolution ────────────────────────────────

    def resolve_env(production)
      config = McpConfig.new
      mcp_env = config.exist? ? config.raw_env : {}

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

    def env_table(env_hash)
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
      path = HINT_STYLE.render(".mcp.json")
      "#{title} #{path}\n\n#{table}"
    end

    def truncate(str, limit)
      return str if str.length <= limit

      "#{str[0, limit - 3]}..."
    end
  end
end

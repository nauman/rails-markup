# frozen_string_literal: true

require "thor"
require "lipgloss"
require_relative "../rails_markup"
require_relative "mcp_config"

module RailsMarkup
  class Cli < Thor
    # ── Lipgloss styles ────────────────────────────────────────
    HEADER_STYLE = Lipgloss::Style.new.bold(true).foreground("#FFFFFF").background("#5C4AE4").padding(0, 1)
    ODD_STYLE    = Lipgloss::Style.new.foreground("#E2E2E2").padding(0, 1)
    EVEN_STYLE   = Lipgloss::Style.new.foreground("#A0A0A0").padding(0, 1)
    MASKED_STYLE = Lipgloss::Style.new.foreground("#6B7280").padding(0, 1)
    LABEL_STYLE  = Lipgloss::Style.new.bold(true).foreground("#FFFFFF")
    HINT_STYLE   = Lipgloss::Style.new.foreground("#6B7280")

    desc "server", "Start HTTP + MCP server"
    method_option :port, type: :numeric, default: 4747, desc: "HTTP server port"
    def server
      srv = RailsMarkup::Server.new(port: options[:port])
      srv.start
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
    method_option :dev_token,  type: :string, desc: "Dev API token (RAILS_MARKUP_DEV_TOKEN)"
    def configure
      env_updates = McpConfig::ENV_KEYS.each_with_object({}) do |(opt, env_key), hash|
        hash[env_key] = options[opt] if options[opt]
      end

      if env_updates.empty?
        say "No options provided. Usage:", :yellow
        say ""
        say "  rails-markup configure --prod-url URL --prod-token TOKEN"
        say "  rails-markup configure --dev-url URL --dev-token TOKEN"
        say ""
        say "Options:"
        McpConfig::ENV_KEYS.each do |opt, env_key|
          say "  --#{opt.tr('_', '-')} VALUE    sets #{env_key}"
        end
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
      $stdout.puts "#{LABEL_STYLE.render(".mcp.json")}  #{HINT_STYLE.render("(#{Dir.pwd})")}"
      if env.empty?
        say "  (no env vars set for rails-markup)"
      else
        $stdout.puts env_table(env)
      end
    end

    def self.exit_on_failure?
      true
    end

    private

    def env_table(env_hash)
      rows = env_hash.map { |k, v| [k, v] }
      Lipgloss::Table.new
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
    end
  end
end

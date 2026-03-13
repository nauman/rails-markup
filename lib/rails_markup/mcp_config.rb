# frozen_string_literal: true

require "json"

module RailsMarkup
  # Reads and writes MCP configuration.
  # Supports three scopes:
  #   "local"  → .mcp.json (project-level, Claude Code)
  #   "global" → ~/.claude/settings.json (Claude Code global)
  #   "codex"  → ~/.codex/config.toml (OpenAI Codex CLI global)
  class McpConfig
    FILE_NAME = ".mcp.json"
    GLOBAL_PATH = File.join(Dir.home, ".claude", "settings.json")
    CODEX_PATH = File.join(Dir.home, ".codex", "config.toml")
    SERVER_KEY = "rails-markup"

    SCOPES = %w[local global codex].freeze

    ENV_KEYS = {
      "prod_url"    => "RAILS_MARKUP_PROD_URL",
      "prod_token"  => "RAILS_MARKUP_PROD_TOKEN",
      "dev_url"     => "RAILS_MARKUP_DEV_URL",
      "mount_path"  => "RAILS_MARKUP_MOUNT_PATH"
    }.freeze

    attr_reader :scope

    def initialize(dir: Dir.pwd, scope: "local")
      @scope = scope
      @dir = dir
      @path = resolve_path(dir, scope)
    end

    def exist?
      File.exist?(@path)
    end

    def path
      @path
    end

    def read
      return {} unless exist?

      toml? ? read_toml : JSON.parse(File.read(@path))
    end

    def env
      read.dig(servers_key, SERVER_KEY, "env") || {}
    end

    alias_method :raw_env, :env

    def update_env(new_vars)
      if toml?
        update_env_toml(new_vars)
      else
        update_env_json(new_vars)
      end
    end

    def display_env
      env.each_with_object({}) do |(k, v), hash|
        hash[k] = k.include?("TOKEN") ? mask(v) : v
      end
    end

    def scope_label
      case @scope
      when "global" then "~/.claude/settings.json"
      when "codex"  then "~/.codex/config.toml"
      else ".mcp.json"
      end
    end

    def global?
      @scope != "local"
    end

    def toml?
      @scope == "codex"
    end

    private

    def servers_key
      toml? ? "mcp_servers" : "mcpServers"
    end

    def resolve_path(dir, scope)
      case scope
      when "global" then GLOBAL_PATH
      when "codex"  then CODEX_PATH
      else File.join(dir, FILE_NAME)
      end
    end

    # ── JSON helpers ───────────────────────────────────────────

    def update_env_json(new_vars)
      config = exist? ? read : {}
      server_entry = skeleton_json.dig("mcpServers", SERVER_KEY)

      config["mcpServers"] ||= {}
      config["mcpServers"][SERVER_KEY] ||= server_entry
      config["mcpServers"][SERVER_KEY]["env"] ||= {}
      config["mcpServers"][SERVER_KEY]["env"].merge!(new_vars)

      File.write(@path, JSON.pretty_generate(config) + "\n")
    end

    def skeleton_json
      cmd, args = detect_command
      {
        "mcpServers" => {
          SERVER_KEY => {
            "type" => "stdio",
            "command" => cmd,
            "args" => args,
            "env" => {}
          }
        }
      }
    end

    # ── TOML helpers (Codex CLI) ───────────────────────────────

    def read_toml
      content = File.read(@path)
      result = {}
      current_section = nil

      content.each_line do |line|
        stripped = line.strip
        next if stripped.empty? || stripped.start_with?("#")

        if stripped =~ /\A\[(.+)\]\z/
          current_section = $1
        elsif stripped =~ /\A(\w+)\s*=\s*(.+)\z/ && current_section
          value = parse_toml_value($2)
          set_nested(result, current_section, $1, value)
        end
      end

      result
    end

    def update_env_toml(new_vars)
      ensure_parent_dir

      if exist?
        content = File.read(@path)
        content = remove_toml_section(content, "mcp_servers.#{SERVER_KEY}")
        content = remove_toml_section(content, "mcp_servers.#{SERVER_KEY}.env")
        content = content.rstrip
        content += "\n\n" unless content.empty?
      else
        content = ""
      end

      cmd, args = detect_command
      existing_env = env
      merged_env = existing_env.merge(new_vars)

      content += toml_server_section(cmd, args, merged_env)
      File.write(@path, content)
    end

    def toml_server_section(cmd, args, env_vars)
      lines = []
      lines << "[mcp_servers.#{SERVER_KEY}]"
      lines << "command = #{toml_value(cmd)}"
      lines << "args = #{toml_value(args)}"
      lines << ""
      lines << "[mcp_servers.#{SERVER_KEY}.env]"
      env_vars.each { |k, v| lines << "#{k} = #{toml_value(v)}" }
      lines << ""
      lines.join("\n")
    end

    def remove_toml_section(content, section_name)
      lines = content.lines
      result = []
      skip = false

      lines.each do |line|
        if line.strip =~ /\A\[(.+)\]\z/
          skip = $1 == section_name
        end

        result << line unless skip
      end

      result.join
    end

    def parse_toml_value(raw)
      case raw
      when /\A"(.*)"\z/  then $1
      when /\Atrue\z/i   then true
      when /\Afalse\z/i  then false
      when /\A\d+\z/     then raw.to_i
      when /\A\[(.+)\]\z/
        $1.split(",").map { |s| parse_toml_value(s.strip) }
      else raw
      end
    end

    def toml_value(val)
      case val
      when String  then %("#{val}")
      when Array   then "[#{val.map { |v| toml_value(v) }.join(", ")}]"
      when true    then "true"
      when false   then "false"
      when Integer then val.to_s
      else %("#{val}")
      end
    end

    def set_nested(hash, section_path, key, value)
      parts = section_path.split(".")
      current = hash
      parts.each { |part| current = (current[part] ||= {}) }
      current[key] = value
    end

    def ensure_parent_dir
      FileUtils.mkdir_p(File.dirname(@path))
    end

    # ── Shared ─────────────────────────────────────────────────

    # Use bin/markup if it exists (install generator creates it),
    # otherwise fall back to bundle exec rails-markup.
    # Global/codex scope always uses absolute paths.
    def detect_command
      bin_wrapper = File.join(@dir, "bin", "markup")
      if File.exist?(bin_wrapper)
        path = global? ? File.expand_path(bin_wrapper) : bin_wrapper
        [path, ["mcp"]]
      else
        ["bundle", ["exec", "rails-markup", "mcp"]]
      end
    end

    def mask(value)
      return value if value.nil? || value.length <= 8

      "#{value[0..3]}****"
    end
  end
end

# frozen_string_literal: true

require "json"

module RailsMarkup
  # Reads and writes .mcp.json configuration.
  # Manages env vars for the rails-markup MCP server entry
  # without disturbing sibling server configs.
  class McpConfig
    FILE_NAME = ".mcp.json"
    SERVER_KEY = "rails-markup"

    ENV_KEYS = {
      "prod_url"    => "RAILS_MARKUP_PROD_URL",
      "prod_token"  => "RAILS_MARKUP_PROD_TOKEN",
      "dev_url"     => "RAILS_MARKUP_DEV_URL",
      "dev_token"   => "RAILS_MARKUP_DEV_TOKEN",
      "mount_path"  => "RAILS_MARKUP_MOUNT_PATH"
    }.freeze

    def initialize(dir: Dir.pwd)
      @path = File.join(dir, FILE_NAME)
    end

    def exist?
      File.exist?(@path)
    end

    def read
      return {} unless exist?

      JSON.parse(File.read(@path))
    end

    def env
      read.dig("mcpServers", SERVER_KEY, "env") || {}
    end

    alias_method :raw_env, :env

    def update_env(new_vars)
      config = exist? ? read : skeleton
      config["mcpServers"] ||= {}
      config["mcpServers"][SERVER_KEY] ||= skeleton.dig("mcpServers", SERVER_KEY)
      config["mcpServers"][SERVER_KEY]["env"] ||= {}
      config["mcpServers"][SERVER_KEY]["env"].merge!(new_vars)

      File.write(@path, JSON.pretty_generate(config) + "\n")
    end

    def display_env
      env.transform_values { |v| mask(v) }
    end

    private

    def skeleton
      {
        "mcpServers" => {
          SERVER_KEY => {
            "type" => "stdio",
            "command" => "ruby",
            "args" => [bin_path, "mcp"],
            "env" => {}
          }
        }
      }
    end

    def bin_path
      File.expand_path("../../bin/rails-markup", __dir__)
    end

    def mask(value)
      return value if value.nil? || value.length <= 8

      "#{value[0..3]}#{"*" * (value.length - 4)}"
    end
  end
end

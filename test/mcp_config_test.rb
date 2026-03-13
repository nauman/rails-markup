# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "json"
require_relative "../lib/rails_markup/mcp_config"

class McpConfigTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir
    @config = RailsMarkup::McpConfig.new(dir: @dir)
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  # -- exist? --

  def test_exist_returns_false_when_no_file
    refute @config.exist?
  end

  def test_exist_returns_true_when_file_present
    write_mcp_json({})
    assert @config.exist?
  end

  # -- read --

  def test_read_returns_empty_hash_when_no_file
    assert_equal({}, @config.read)
  end

  def test_read_returns_parsed_json
    data = { "mcpServers" => { "rails-markup" => { "env" => {} } } }
    write_mcp_json(data)
    assert_equal data, @config.read
  end

  # -- env --

  def test_env_returns_empty_hash_when_no_file
    assert_equal({}, @config.env)
  end

  def test_env_returns_empty_hash_when_no_server_entry
    write_mcp_json({ "mcpServers" => {} })
    assert_equal({}, @config.env)
  end

  def test_env_returns_env_vars
    write_mcp_json({
      "mcpServers" => {
        "rails-markup" => { "env" => { "RAILS_MARKUP_PROD_URL" => "https://example.com" } }
      }
    })
    assert_equal({ "RAILS_MARKUP_PROD_URL" => "https://example.com" }, @config.env)
  end

  # -- update_env --

  def test_update_env_creates_file_when_missing
    @config.update_env("RAILS_MARKUP_PROD_URL" => "https://example.com")

    assert @config.exist?
    assert_equal "https://example.com", @config.env["RAILS_MARKUP_PROD_URL"]
  end

  def test_update_env_creates_skeleton_with_correct_args
    @config.update_env("RAILS_MARKUP_PROD_URL" => "https://example.com")

    data = @config.read
    server = data["mcpServers"]["rails-markup"]
    assert_equal "stdio", server["type"]
    # Without bin/markup present, falls back to bundle exec
    assert_equal "bundle", server["command"]
    assert_equal ["exec", "rails-markup", "mcp"], server["args"]
  end

  def test_update_env_merges_without_replacing
    @config.update_env("RAILS_MARKUP_PROD_URL" => "https://example.com")
    @config.update_env("RAILS_MARKUP_PROD_TOKEN" => "secret123")

    env = @config.env
    assert_equal "https://example.com", env["RAILS_MARKUP_PROD_URL"]
    assert_equal "secret123", env["RAILS_MARKUP_PROD_TOKEN"]
  end

  def test_update_env_preserves_sibling_servers
    write_mcp_json({
      "mcpServers" => {
        "other-server" => { "command" => "other", "args" => [] },
        "rails-markup" => { "type" => "stdio", "command" => "ruby", "args" => ["mcp"], "env" => {} }
      }
    })

    @config.update_env("RAILS_MARKUP_DEV_URL" => "http://localhost:3004")

    data = @config.read
    assert data["mcpServers"].key?("other-server")
    assert_equal "other", data["mcpServers"]["other-server"]["command"]
  end

  def test_update_env_overwrites_existing_key
    @config.update_env("RAILS_MARKUP_PROD_URL" => "https://old.com")
    @config.update_env("RAILS_MARKUP_PROD_URL" => "https://new.com")

    assert_equal "https://new.com", @config.env["RAILS_MARKUP_PROD_URL"]
  end

  # -- update_env refreshes command/args --

  def test_update_env_refreshes_command_when_bin_markup_exists
    # Start with a stale config using old ruby path
    write_mcp_json({
      "mcpServers" => {
        "rails-markup" => {
          "type" => "stdio",
          "command" => "ruby",
          "args" => ["/old/path/bin/rails-markup", "mcp"],
          "env" => { "RAILS_MARKUP_DEV_URL" => "http://localhost:3000" }
        }
      }
    })

    # Create bin/markup so detect_command finds it
    bin_dir = File.join(@dir, "bin")
    FileUtils.mkdir_p(bin_dir)
    File.write(File.join(bin_dir, "markup"), "#!/bin/bash\necho mcp")

    @config.update_env("RAILS_MARKUP_DEV_URL" => "http://localhost:3004")

    data = @config.read
    server = data["mcpServers"]["rails-markup"]
    # Local scope uses relative path "bin/markup"
    assert_equal "bin/markup", server["command"],
      "Should refresh command to bin/markup, got: #{server["command"]}"
    assert_equal ["mcp"], server["args"],
      "Should refresh args to [\"mcp\"], got: #{server["args"]}"
  end

  def test_update_env_refreshes_command_to_bundle_fallback
    # Start with stale config
    write_mcp_json({
      "mcpServers" => {
        "rails-markup" => {
          "type" => "stdio",
          "command" => "ruby",
          "args" => ["/old/path/bin/rails-markup", "mcp"],
          "env" => {}
        }
      }
    })

    # No bin/markup present, should fall back to bundle exec
    @config.update_env("RAILS_MARKUP_DEV_URL" => "http://localhost:3004")

    data = @config.read
    server = data["mcpServers"]["rails-markup"]
    assert_equal "bundle", server["command"],
      "Should refresh command to bundle, got: #{server["command"]}"
    assert_equal ["exec", "rails-markup", "mcp"], server["args"]
  end

  # -- display_env --

  def test_display_env_masks_tokens_but_not_urls
    @config.update_env(
      "RAILS_MARKUP_PROD_URL" => "https://inventlist.com",
      "RAILS_MARKUP_PROD_TOKEN" => "ebYsw895N9YKwWFLqS2dxTLU"
    )

    display = @config.display_env
    assert_equal "https://inventlist.com", display["RAILS_MARKUP_PROD_URL"]
    assert_equal "ebYs****", display["RAILS_MARKUP_PROD_TOKEN"]
  end

  def test_display_env_does_not_mask_short_values
    @config.update_env("RAILS_MARKUP_DEV_TOKEN" => "short")

    display = @config.display_env
    assert_equal "short", display["RAILS_MARKUP_DEV_TOKEN"]
  end

  # -- scope_label --

  def test_scope_label_local
    assert_equal ".mcp.json", @config.scope_label
  end

  def test_scope_label_global
    config = RailsMarkup::McpConfig.new(dir: @dir, scope: "global")
    assert_equal "~/.claude/settings.json", config.scope_label
  end

  def test_scope_label_codex
    config = RailsMarkup::McpConfig.new(dir: @dir, scope: "codex")
    assert_equal "~/.codex/config.toml", config.scope_label
  end

  # -- global scope (Claude Code) --

  def test_global_resolves_to_claude_settings_path
    config = RailsMarkup::McpConfig.new(dir: @dir, scope: "global")
    assert_equal RailsMarkup::McpConfig::GLOBAL_PATH, config.path
  end

  def test_global_preserves_sibling_keys
    global_dir = Dir.mktmpdir
    global_path = File.join(global_dir, "settings.json")

    # Stub GLOBAL_PATH for this test
    config = RailsMarkup::McpConfig.new(dir: @dir, scope: "global")
    config.instance_variable_set(:@path, global_path)

    # Pre-populate with non-MCP settings
    File.write(global_path, JSON.pretty_generate({
      "enabledPlugins" => ["analysis"],
      "alwaysThinkingEnabled" => true
    }))

    config.update_env("RAILS_MARKUP_PROD_URL" => "https://example.com")

    data = JSON.parse(File.read(global_path))
    assert_equal ["analysis"], data["enabledPlugins"]
    assert_equal true, data["alwaysThinkingEnabled"]
    assert_equal "https://example.com", data.dig("mcpServers", "rails-markup", "env", "RAILS_MARKUP_PROD_URL")
  ensure
    FileUtils.remove_entry(global_dir) if global_dir
  end

  def test_global_uses_absolute_path_for_bin_wrapper
    bin_dir = File.join(@dir, "bin")
    FileUtils.mkdir_p(bin_dir)
    File.write(File.join(bin_dir, "markup"), "#!/bin/bash\necho mcp")

    config = RailsMarkup::McpConfig.new(dir: @dir, scope: "global")
    global_path = File.join(@dir, "global_settings.json")
    config.instance_variable_set(:@path, global_path)

    config.update_env("RAILS_MARKUP_PROD_URL" => "https://example.com")

    data = JSON.parse(File.read(global_path))
    command = data.dig("mcpServers", "rails-markup", "command")
    assert command.start_with?("/"), "Global command should be absolute path, got: #{command}"
  end

  # -- codex scope (TOML) --

  def test_codex_resolves_to_codex_config_path
    config = RailsMarkup::McpConfig.new(dir: @dir, scope: "codex")
    assert_equal RailsMarkup::McpConfig::CODEX_PATH, config.path
  end

  def test_codex_creates_toml_file
    toml_path = File.join(@dir, "config.toml")
    config = RailsMarkup::McpConfig.new(dir: @dir, scope: "codex")
    config.instance_variable_set(:@path, toml_path)

    config.update_env("RAILS_MARKUP_PROD_URL" => "https://example.com")

    assert File.exist?(toml_path)
    content = File.read(toml_path)
    assert_match(/\[mcp_servers\.rails-markup\]/, content)
    assert_match(/RAILS_MARKUP_PROD_URL = "https:\/\/example.com"/, content)
  end

  def test_codex_reads_toml_env
    toml_path = File.join(@dir, "config.toml")
    config = RailsMarkup::McpConfig.new(dir: @dir, scope: "codex")
    config.instance_variable_set(:@path, toml_path)

    File.write(toml_path, <<~TOML)
      [mcp_servers.rails-markup]
      command = "bundle"
      args = ["exec", "rails-markup", "mcp"]

      [mcp_servers.rails-markup.env]
      RAILS_MARKUP_PROD_URL = "https://example.com"
      RAILS_MARKUP_PROD_TOKEN = "secret123"
    TOML

    env = config.env
    assert_equal "https://example.com", env["RAILS_MARKUP_PROD_URL"]
    assert_equal "secret123", env["RAILS_MARKUP_PROD_TOKEN"]
  end

  def test_codex_preserves_other_toml_sections
    toml_path = File.join(@dir, "config.toml")
    config = RailsMarkup::McpConfig.new(dir: @dir, scope: "codex")
    config.instance_variable_set(:@path, toml_path)

    File.write(toml_path, <<~TOML)
      [mcp_servers.other-server]
      command = "npx"
      args = ["-y", "other-mcp"]
    TOML

    config.update_env("RAILS_MARKUP_PROD_URL" => "https://example.com")

    content = File.read(toml_path)
    assert_match(/\[mcp_servers\.other-server\]/, content)
    assert_match(/command = "npx"/, content)
    assert_match(/\[mcp_servers\.rails-markup\]/, content)
  end

  def test_codex_merges_env_on_update
    toml_path = File.join(@dir, "config.toml")
    config = RailsMarkup::McpConfig.new(dir: @dir, scope: "codex")
    config.instance_variable_set(:@path, toml_path)

    config.update_env("RAILS_MARKUP_PROD_URL" => "https://example.com")
    config.update_env("RAILS_MARKUP_PROD_TOKEN" => "token123")

    env = config.env
    assert_equal "https://example.com", env["RAILS_MARKUP_PROD_URL"]
    assert_equal "token123", env["RAILS_MARKUP_PROD_TOKEN"]
  end

  def test_codex_uses_absolute_path_for_bin_wrapper
    bin_dir = File.join(@dir, "bin")
    FileUtils.mkdir_p(bin_dir)
    File.write(File.join(bin_dir, "markup"), "#!/bin/bash\necho mcp")

    toml_path = File.join(@dir, "config.toml")
    config = RailsMarkup::McpConfig.new(dir: @dir, scope: "codex")
    config.instance_variable_set(:@path, toml_path)

    config.update_env("RAILS_MARKUP_PROD_URL" => "https://example.com")

    content = File.read(toml_path)
    # Should have absolute path in command
    assert_match(/command = "\//, content)
  end

  private

  def write_mcp_json(data)
    File.write(File.join(@dir, ".mcp.json"), JSON.pretty_generate(data))
  end
end

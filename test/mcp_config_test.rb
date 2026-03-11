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
    assert_equal "ruby", server["command"]
    assert_includes server["args"].last, "mcp"
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

  # -- display_env --

  def test_display_env_masks_long_values
    @config.update_env(
      "RAILS_MARKUP_PROD_URL" => "https://inventlist.com",
      "RAILS_MARKUP_PROD_TOKEN" => "ebYsw895N9YKwWFLqS2dxTLU"
    )

    display = @config.display_env
    # "https://inventlist.com" = 22 chars → 4 shown + 18 masked
    assert_equal "http" + "*" * 18, display["RAILS_MARKUP_PROD_URL"]
    # "ebYsw895N9YKwWFLqS2dxTLU" = 24 chars → 4 shown + 20 masked
    assert_equal "ebYs" + "*" * 20, display["RAILS_MARKUP_PROD_TOKEN"]
  end

  def test_display_env_does_not_mask_short_values
    @config.update_env("RAILS_MARKUP_DEV_TOKEN" => "short")

    display = @config.display_env
    assert_equal "short", display["RAILS_MARKUP_DEV_TOKEN"]
  end

  private

  def write_mcp_json(data)
    File.write(File.join(@dir, ".mcp.json"), JSON.pretty_generate(data))
  end
end

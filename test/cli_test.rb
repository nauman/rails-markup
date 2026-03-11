# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "json"
require_relative "../lib/rails_markup/cli"

class CliTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir
    @original_dir = Dir.pwd
    Dir.chdir(@dir)
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.remove_entry(@dir)
  end

  # -- configure --

  def test_configure_creates_mcp_json
    run_cli("configure", "--prod-url", "https://example.com", "--prod-token", "abc123")

    assert File.exist?(File.join(@dir, ".mcp.json"))
    config = RailsMarkup::McpConfig.new(dir: @dir)
    assert_equal "https://example.com", config.env["RAILS_MARKUP_PROD_URL"]
    assert_equal "abc123", config.env["RAILS_MARKUP_PROD_TOKEN"]
  end

  def test_configure_merges_env_vars
    run_cli("configure", "--prod-url", "https://example.com")
    run_cli("configure", "--dev-url", "http://localhost:3004")

    config = RailsMarkup::McpConfig.new(dir: @dir)
    assert_equal "https://example.com", config.env["RAILS_MARKUP_PROD_URL"]
    assert_equal "http://localhost:3004", config.env["RAILS_MARKUP_DEV_URL"]
  end

  def test_configure_sets_mount_path
    run_cli("configure", "--dev-url", "http://localhost:3000", "--mount-path", "/feedback")

    config = RailsMarkup::McpConfig.new(dir: @dir)
    assert_equal "/feedback", config.env["RAILS_MARKUP_MOUNT_PATH"]
    assert_equal "http://localhost:3000", config.env["RAILS_MARKUP_DEV_URL"]
  end

  def test_configure_no_options_shows_usage
    output = capture_output { run_cli("configure") }
    assert_match(/No options provided/, output)
    assert_match(/--prod-url/, output)
  end

  # -- status --

  def test_status_no_file_shows_warning
    output = capture_output { run_cli("status") }
    assert_match(/No .mcp.json found/, output)
  end

  def test_status_shows_urls_unmasked_and_tokens_masked
    run_cli("configure", "--prod-url", "https://inventlist.com", "--prod-token", "ebYsw895N9YKwWFLqS2dxTLU")
    output = capture_output { run_cli("status") }

    assert_match(/https:\/\/inventlist\.com/, output)  # URLs shown in full
    assert_match(/ebYs\*+/, output)                     # Tokens masked
    refute_match(/ebYsw895N9YKwWFLqS2dxTLU/, output)   # Full token never shown
  end

  def test_status_shows_empty_env
    File.write(File.join(@dir, ".mcp.json"), JSON.pretty_generate({
      "mcpServers" => { "rails-markup" => { "env" => {} } }
    }))

    output = capture_output { run_cli("status") }
    assert_match(/no env vars set/, output)
  end

  # -- setup-production --

  def test_setup_production_generates_token_and_saves
    run_cli("setup-production", "--url", "https://myapp.com")

    config = RailsMarkup::McpConfig.new(dir: @dir)
    assert_equal "https://myapp.com", config.env["RAILS_MARKUP_PROD_URL"]

    token = config.env["RAILS_MARKUP_PROD_TOKEN"]
    refute_nil token
    assert token.length >= 20, "Token should be at least 20 chars, got #{token.length}"
  end

  def test_setup_production_shows_instructions
    output = capture_output { run_cli("setup-production", "--url", "https://myapp.com") }

    assert_match(/Production token generated/, output)
    assert_match(/Token:/, output)
    assert_match(/rails credentials:edit/, output)
    assert_match(/config\.api_token/, output)
    assert_match(/bin\/markup pending --production/, output)
  end

  def test_setup_production_without_url_shows_error
    output = capture_output { run_cli("setup-production") }
    assert_match(/Usage/, output)
  end

  def test_setup_production_preserves_existing_config
    run_cli("configure", "--dev-url", "http://localhost:3000")
    run_cli("setup-production", "--url", "https://myapp.com")

    config = RailsMarkup::McpConfig.new(dir: @dir)
    assert_equal "http://localhost:3000", config.env["RAILS_MARKUP_DEV_URL"]
    assert_equal "https://myapp.com", config.env["RAILS_MARKUP_PROD_URL"]
    refute_nil config.env["RAILS_MARKUP_PROD_TOKEN"]
  end

  # -- fetch --

  def test_fetch_without_url_shows_error
    output = capture_output { run_cli("fetch") }
    assert_match(/No dev URL/, output)
    assert_match(/bin\/markup configure/, output)
  end

  def test_fetch_production_without_token_shows_error
    run_cli("configure", "--prod-url", "https://example.com")
    output = capture_output { run_cli("fetch", "--env=production") }
    assert_match(/No production token/, output)
  end

  # -- McpConfig detect_command --

  def test_mcp_json_uses_bin_markup_when_present
    FileUtils.mkdir_p(File.join(@dir, "bin"))
    File.write(File.join(@dir, "bin", "markup"), "#!/usr/bin/env ruby")

    run_cli("configure", "--dev-url", "http://localhost:3000")

    config = JSON.parse(File.read(File.join(@dir, ".mcp.json")))
    server = config["mcpServers"]["rails-markup"]
    assert server["command"].end_with?("bin/markup"), "Expected bin/markup, got #{server["command"]}"
    assert_equal ["mcp"], server["args"]
  end

  def test_mcp_json_falls_back_to_bundle_exec
    run_cli("configure", "--dev-url", "http://localhost:3000")

    config = JSON.parse(File.read(File.join(@dir, ".mcp.json")))
    server = config["mcpServers"]["rails-markup"]
    assert_equal "bundle", server["command"]
    assert_equal ["exec", "rails-markup", "mcp"], server["args"]
  end

  # -- pending --

  def test_pending_without_url_shows_error
    output = capture_output { run_cli("pending") }
    assert_match(/No dev URL/, output)
    assert_match(/bin\/markup configure/, output)
  end

  def test_pending_production_without_url_shows_error
    output = capture_output { run_cli("pending", "--production") }
    assert_match(/No production URL/, output)
  end

  def test_pending_production_without_token_shows_error
    run_cli("configure", "--prod-url", "https://example.com")
    output = capture_output { run_cli("pending", "--production") }
    assert_match(/No production token/, output)
  end

  # -- resolve --

  def test_resolve_without_id_shows_error
    output = capture_output { run_cli("resolve") }
    assert_match(/annotation ID/i, output)
  end

  # -- dismiss --

  def test_dismiss_without_id_shows_error
    output = capture_output { run_cli("dismiss") }
    assert_match(/annotation ID/i, output)
  end

  # -- reply --

  def test_reply_without_id_shows_error
    output = capture_output { run_cli("reply") }
    assert_match(/annotation ID/i, output)
  end

  def test_reply_without_message_shows_error
    run_cli("configure", "--dev-url", "http://localhost:3000")
    output = capture_output { run_cli("reply", "42") }
    assert_match(/message/i, output)
  end

  # -- acknowledge --

  def test_acknowledge_without_id_shows_error
    output = capture_output { run_cli("acknowledge") }
    assert_match(/annotation ID/i, output)
  end

  # -- fetch (legacy, still works) --

  def test_fetch_without_url_shows_error
    output = capture_output { run_cli("fetch") }
    assert_match(/No dev URL/, output)
    assert_match(/bin\/markup configure/, output)
  end

  def test_fetch_production_without_token_shows_error
    run_cli("configure", "--prod-url", "https://example.com")
    output = capture_output { run_cli("fetch", "--env=production") }
    assert_match(/No production token/, output)
  end

  # -- help --

  def test_bare_command_shows_help
    output = capture_output { run_cli("help") }
    assert_match(/server/, output)
    assert_match(/configure/, output)
    assert_match(/status/, output)
    assert_match(/pending/, output)
    assert_match(/resolve/, output)
    assert_match(/dismiss/, output)
    assert_match(/reply/, output)
    assert_match(/acknowledge/, output)
    assert_match(/setup-production/, output)
  end

  private

  def run_cli(*args)
    RailsMarkup::Cli.start(args)
  end

  def capture_output
    out = StringIO.new
    $stdout = out
    yield
    strip_ansi(out.string)
  ensure
    $stdout = STDOUT
  end

  def strip_ansi(str)
    str.gsub(/\e\[[0-9;]*m/, "")
  end
end

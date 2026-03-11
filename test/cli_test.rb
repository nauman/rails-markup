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

  def test_status_shows_masked_tokens
    run_cli("configure", "--prod-url", "https://inventlist.com", "--prod-token", "ebYsw895N9YKwWFLqS2dxTLU")
    output = capture_output { run_cli("status") }

    assert_match(/RAILS_MARKUP_PROD_URL/, output)
    assert_match(/http\*+/, output)
    assert_match(/ebYs\*+/, output)
    refute_match(/ebYsw895N9YKwWFLqS2dxTLU/, output)
  end

  def test_status_shows_empty_env
    File.write(File.join(@dir, ".mcp.json"), JSON.pretty_generate({
      "mcpServers" => { "rails-markup" => { "env" => {} } }
    }))

    output = capture_output { run_cli("status") }
    assert_match(/no env vars set/, output)
  end

  # -- help --

  def test_bare_command_shows_help
    output = capture_output { run_cli("help") }
    assert_match(/server/, output)
    assert_match(/configure/, output)
    assert_match(/status/, output)
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

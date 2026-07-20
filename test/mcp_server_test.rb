# frozen_string_literal: true

require_relative "test_helper"
require "stringio"

class McpServerTest < Minitest::Test
  def setup
    @store  = RailsMarkup::Store.new
    @output = StringIO.new
  end

  # ── Protocol ───────────────────────────────────────────────

  def test_initialize_response
    input = StringIO.new(jsonrpc_request(1, "initialize", { protocolVersion: "2024-11-05" }))
    mcp = RailsMarkup::McpServer.new(store: @store, input: input, output: @output)
    mcp.start

    response = parse_output
    assert_equal "2.0", response["jsonrpc"]
    assert_equal 1, response["id"]
    assert_equal "rails-markup", response["result"]["serverInfo"]["name"]
  end

  def test_initialize_negotiates_protocol_version
    input = StringIO.new(jsonrpc_request(1, "initialize", { protocolVersion: "2025-06-18" }))
    mcp = RailsMarkup::McpServer.new(store: @store, input: input, output: @output)
    mcp.start

    response = parse_output
    assert_equal "2025-06-18", response["result"]["protocolVersion"]
  end

  def test_initialize_falls_back_for_unknown_protocol_version
    input = StringIO.new(jsonrpc_request(1, "initialize", { protocolVersion: "9999-01-01" }))
    mcp = RailsMarkup::McpServer.new(store: @store, input: input, output: @output)
    mcp.start

    response = parse_output
    assert_equal "2025-06-18", response["result"]["protocolVersion"]
  end

  # ── Tools list (8 unified tools) ───────────────────────────

  def test_tools_list_advertises_exactly_five_canonical_tools
    input = StringIO.new(jsonrpc_request(1, "tools/list"))
    mcp = RailsMarkup::McpServer.new(store: @store, input: input, output: @output)
    mcp.start

    names = parse_output["result"]["tools"].map { |t| t["name"] }
    expected = %w[
      rails_markup_read
      rails_markup_watch
      rails_markup_transition
      rails_markup_reply
      rails_markup_dismiss
    ]
    assert_equal expected, names
  end

  def test_canonical_tool_schemas_are_closed_and_unambiguous
    input = StringIO.new(jsonrpc_request(1, "tools/list"))
    mcp = RailsMarkup::McpServer.new(store: @store, input: input, output: @output)
    mcp.start

    tools = parse_output["result"]["tools"].to_h { |tool| [tool["name"], tool] }
    assert tools.values.all? { |tool| tool.dig("inputSchema", "additionalProperties") == false }

    read = tools.fetch("rails_markup_read")["inputSchema"]
    assert_equal %w[resource], read["required"]
    assert_equal %w[pending sessions session annotation], read.dig("properties", "resource", "enum")
    assert_equal %w[development production], read.dig("properties", "environment", "enum")
    assert_equal %w[resource environment sessionId annotationId], read["properties"].keys

    watch = tools.fetch("rails_markup_watch")["inputSchema"]
    assert_equal [], watch["required"]
    assert_equal %w[sessionId timeoutSeconds batchWindowSeconds], watch["properties"].keys

    transition = tools.fetch("rails_markup_transition")["inputSchema"]
    assert_equal %w[action annotationId], transition["required"]
    assert_equal %w[acknowledge resolve], transition.dig("properties", "action", "enum")
    assert_equal %w[action annotationId summary environment], transition["properties"].keys

    assert_equal %w[annotationId message], tools.fetch("rails_markup_reply").dig("inputSchema", "required")
    assert_equal %w[annotationId reason], tools.fetch("rails_markup_dismiss").dig("inputSchema", "required")
  end

  def test_canonical_tools_advertise_safety_annotations
    input = StringIO.new(jsonrpc_request(1, "tools/list"))
    mcp = RailsMarkup::McpServer.new(store: @store, input: input, output: @output)
    mcp.start

    tools = parse_output["result"]["tools"].to_h { |tool| [tool["name"], tool] }
    assert_equal true, tools.fetch("rails_markup_read").dig("annotations", "readOnlyHint")
    assert_equal true, tools.fetch("rails_markup_watch").dig("annotations", "readOnlyHint")
    assert_equal false, tools.fetch("rails_markup_transition").dig("annotations", "destructiveHint")
    assert_equal false, tools.fetch("rails_markup_reply").dig("annotations", "destructiveHint")
    assert_equal true, tools.fetch("rails_markup_dismiss").dig("annotations", "destructiveHint")
  end

  def test_canonical_read_dispatches_each_resource
    session = @store.create_session(url: "http://example.com")
    annotation = @store.create_annotation(session_id: session.id, target: "div", content: "fix this")

    assert_equal 1, call_tool("rails_markup_read", resource: "sessions").size
    assert_equal session.id, call_tool("rails_markup_read", resource: "session", sessionId: session.id)["id"]
    assert_equal annotation.id, call_tool("rails_markup_read", resource: "annotation", annotationId: annotation.id)["id"]
    assert_equal annotation.id, call_tool("rails_markup_read", resource: "pending").first["id"]
  end

  def test_canonical_transition_dispatches_each_action
    acknowledged = create_test_annotation
    resolved = create_test_annotation

    assert_equal "acknowledged", call_tool(
      "rails_markup_transition", action: "acknowledge", annotationId: acknowledged.id
    )["status"]
    result = call_tool(
      "rails_markup_transition", action: "resolve", annotationId: resolved.id, summary: "Fixed padding"
    )
    assert_equal "resolved", result["status"]
    assert_equal "Fixed padding", result["thread"].first["message"]
  end

  def test_canonical_tools_validate_enums_and_conditional_ids
    invalid_calls = [
      ["rails_markup_read", { resource: "unknown" }],
      ["rails_markup_read", { resource: "session" }],
      ["rails_markup_read", { resource: "annotation" }],
      ["rails_markup_transition", { action: "close", annotationId: "123" }]
    ]

    invalid_calls.each do |name, arguments|
      response = call_tool_response(name, **arguments)
      assert_equal true, response.dig("result", "isError"), "expected #{name} to reject #{arguments.keys}"
    end
  end

  def test_canonical_and_legacy_tools_reject_unknown_arguments
    calls = [
      ["rails_markup_read", { resource: "pending", baseUrl: "https://attacker.test" }],
      ["rails_markup_reply", { annotationId: "123", message: "safe", token: "caller-secret" }],
      ["rails_markup_get_pending", { url: "https://attacker.test" }],
      ["rails_markup_fetch_production", { markAcknowledged: true }]
    ]

    calls.each do |name, arguments|
      response = nil
      capture_stderr { response = call_tool_response(name, **arguments) }
      assert_equal true, response.dig("result", "isError"), "expected #{name} to reject unknown arguments"
      assert_match(/Remove unsupported arguments/, response.dig("result", "content", 0, "text"))
    end
  end

  def test_legacy_alias_table_maps_every_supported_name_to_canonical_tools
    expected = {
      "rails_markup_sessions" => ["rails_markup_read", { "resource" => "sessions" }],
      "rails_markup_list_sessions" => ["rails_markup_read", { "resource" => "sessions" }],
      "rails_markup_session" => ["rails_markup_read", { "resource" => "session" }],
      "rails_markup_get_session" => ["rails_markup_read", { "resource" => "session" }],
      "rails_markup_pending" => ["rails_markup_read", { "resource" => "pending" }],
      "rails_markup_get_pending" => ["rails_markup_read", { "resource" => "pending" }],
      "rails_markup_get_all_pending" => ["rails_markup_read", { "resource" => "pending" }],
      "rails_markup_fetch_production" => ["rails_markup_read", { "resource" => "pending", "environment" => "production" }],
      "rails_markup_watch_annotations" => ["rails_markup_watch", {}],
      "rails_markup_acknowledge" => ["rails_markup_transition", { "action" => "acknowledge" }],
      "rails_markup_resolve" => ["rails_markup_transition", { "action" => "resolve" }],
      "rails_markup_resolve_production" => ["rails_markup_transition", { "action" => "resolve", "environment" => "production" }],
      "rails_markup_reply_production" => ["rails_markup_reply", { "environment" => "production" }],
      "rails_markup_dismiss_production" => ["rails_markup_dismiss", { "environment" => "production" }]
    }

    actual = RailsMarkup::McpServer::LEGACY_ALIASES.transform_values do |adapter|
      [adapter.fetch(:handler), adapter.fetch(:inject, {})]
    end
    assert_equal expected, actual
  end

  def test_legacy_production_read_never_auto_acknowledges
    ENV["RAILS_MARKUP_PROD_URL"] = "https://configured.test"
    ENV["RAILS_MARKUP_PROD_TOKEN"] = "configured-secret"
    input = StringIO.new(jsonrpc_request(1, "tools/call", {
      name: "rails_markup_fetch_production", arguments: {}
    }))
    mcp = RailsMarkup::McpServer.new(store: @store, input: input, output: @output)
    response = Struct.new(:code, :body).new("200", '{"annotations":[{"id":"abc"}]}')
    response.define_singleton_method(:is_a?) { |klass| klass == Net::HTTPSuccess }
    patch_calls = []
    mcp.define_singleton_method(:http_get) { |_url, token: nil| response }
    mcp.define_singleton_method(:http_patch) { |*args| patch_calls << args }

    capture_stderr { mcp.start }
    assert_empty patch_calls
    assert_equal false, parse_output.dig("result", "isError") || false
  ensure
    ENV.delete("RAILS_MARKUP_PROD_URL")
    ENV.delete("RAILS_MARKUP_PROD_TOKEN")
  end

  # ── Sessions (new names) ───────────────────────────────────

  def test_sessions_empty
    result = call_tool("rails_markup_sessions")
    assert_equal [], result
  end

  def test_sessions_with_data
    @store.create_session(url: "http://example.com")
    result = call_tool("rails_markup_sessions")
    assert_equal 1, result.size
  end

  def test_session_by_id
    session = @store.create_session(url: "http://example.com")
    result = call_tool("rails_markup_session", sessionId: session.id)
    assert_equal session.id, result["id"]
  end

  # ── Pending (unified: replaces get_all_pending + get_pending) ──

  def test_pending_all
    session = @store.create_session(url: "http://example.com")
    @store.create_annotation(session_id: session.id, target: "div", content: "fix this")
    result = call_tool("rails_markup_pending")
    assert_equal 1, result.size
    assert_equal "fix this", result.first["content"]
  end

  def test_pending_by_session
    session = @store.create_session(url: "http://example.com")
    @store.create_annotation(session_id: session.id, target: "div", content: "fix this")
    result = call_tool("rails_markup_pending", sessionId: session.id)
    assert_equal 1, result.size
  end

  def test_pending_production_without_url_returns_error
    result = call_tool("rails_markup_pending", environment: "production")
    assert_match(/No production URL/, result["error"])
  end

  # ── Actions (new names) ────────────────────────────────────

  def test_acknowledge
    ann = create_test_annotation
    result = call_tool("rails_markup_acknowledge", annotationId: ann.id)
    assert_equal "acknowledged", result["status"]
  end

  def test_resolve
    ann = create_test_annotation
    result = call_tool("rails_markup_resolve", annotationId: ann.id, summary: "Fixed padding")
    assert_equal "resolved", result["status"]
  end

  def test_dismiss
    ann = create_test_annotation
    result = call_tool("rails_markup_dismiss", annotationId: ann.id, reason: "Working as intended")
    assert_equal "dismissed", result["status"]
  end

  def test_reply
    ann = create_test_annotation
    result = call_tool("rails_markup_reply", annotationId: ann.id, message: "Can you clarify?")
    assert_equal 1, result["thread"].size
    assert_equal "Can you clarify?", result["thread"].first["message"]
  end

  # ── Production environment routing ─────────────────────────

  def test_resolve_production_without_url_returns_error
    ann = create_test_annotation
    result = call_tool("rails_markup_resolve", annotationId: ann.id, environment: "production")
    assert_match(/No production URL/, result["error"])
  end

  def test_dismiss_production_without_url_returns_error
    ann = create_test_annotation
    result = call_tool("rails_markup_dismiss", annotationId: ann.id, reason: "not applicable", environment: "production")
    assert_match(/No production URL/, result["error"])
  end

  def test_reply_production_without_url_returns_error
    ann = create_test_annotation
    result = call_tool("rails_markup_reply", annotationId: ann.id, message: "test", environment: "production")
    assert_match(/No production URL/, result["error"])
  end

  def test_acknowledge_production_without_url_returns_error
    ann = create_test_annotation
    result = call_tool("rails_markup_acknowledge", annotationId: ann.id, environment: "production")
    assert_match(/No production URL/, result["error"])
  end

  # ── Legacy aliases ─────────────────────────────────────────

  def test_legacy_get_all_pending_dispatches_to_pending
    session = @store.create_session(url: "http://example.com")
    @store.create_annotation(session_id: session.id, target: "div", content: "fix this")
    result = call_tool("rails_markup_get_all_pending")
    assert_equal 1, result.size
  end

  def test_legacy_list_sessions_dispatches_to_sessions
    @store.create_session(url: "http://example.com")
    result = call_tool("rails_markup_list_sessions")
    assert_equal 1, result.size
  end

  def test_legacy_get_session_dispatches_to_session
    session = @store.create_session(url: "http://example.com")
    result = call_tool("rails_markup_get_session", sessionId: session.id)
    assert_equal session.id, result["id"]
  end

  def test_legacy_get_pending_dispatches_to_pending
    session = @store.create_session(url: "http://example.com")
    @store.create_annotation(session_id: session.id, target: "div", content: "fix")
    result = call_tool("rails_markup_get_pending", sessionId: session.id)
    assert_equal 1, result.size
  end

  def test_legacy_watch_annotations_dispatches_to_watch
    # Just verify it dispatches without error (watch would block, so we can't fully test)
    assert RailsMarkup::McpServer::LEGACY_ALIASES.key?("rails_markup_watch_annotations")
    assert_equal "rails_markup_watch", RailsMarkup::McpServer::LEGACY_ALIASES["rails_markup_watch_annotations"][:handler]
  end

  def test_legacy_fetch_production_injects_environment
    result = call_tool("rails_markup_fetch_production")
    assert_match(/No production URL/, result["error"])
  end

  def test_legacy_resolve_production_injects_environment
    ann = create_test_annotation
    result = call_tool("rails_markup_resolve_production", annotationId: ann.id)
    assert_match(/No production URL/, result["error"])
  end

  def test_legacy_emits_deprecation_to_stderr
    session = @store.create_session(url: "http://example.com")
    @store.create_annotation(session_id: session.id, target: "div", content: "fix")

    stderr_output = capture_stderr do
      call_tool("rails_markup_get_all_pending")
    end

    assert_match(/DEPRECATED/, stderr_output)
    assert_match(/rails_markup_get_all_pending/, stderr_output)
    assert_match(/rails_markup_read/, stderr_output)
  end

  # ── Unknown tool ───────────────────────────────────────────

  def test_unknown_tool
    input = StringIO.new(jsonrpc_request(1, "tools/call", {
      name: "rails_markup_nonexistent", arguments: {}
    }))
    mcp = RailsMarkup::McpServer.new(store: @store, input: input, output: @output)
    mcp.start

    response = parse_output
    assert_equal true, response.dig("result", "isError")
    assert_match(/tools\/list/, response.dig("result", "content", 0, "text"))
  end

  # ── Misc ───────────────────────────────────────────────────

  def test_ping
    input = StringIO.new(jsonrpc_request(1, "ping"))
    mcp = RailsMarkup::McpServer.new(store: @store, input: input, output: @output)
    mcp.start

    response = parse_output
    assert_equal 1, response["id"]
    assert response["result"]
  end

  def test_multiple_requests
    lines = [
      jsonrpc_request(1, "initialize", { protocolVersion: "2024-11-05" }),
      jsonrpc_request(2, "tools/list")
    ].join
    input = StringIO.new(lines)
    mcp = RailsMarkup::McpServer.new(store: @store, input: input, output: @output)
    mcp.start

    responses = @output.string.lines.map { |l| JSON.parse(l) }
    assert_equal 2, responses.size
    assert_equal 1, responses[0]["id"]
    assert_equal 2, responses[1]["id"]
  end

  # ── Config ─────────────────────────────────────────────────

  def test_mount_path_defaults_to_admin_annotations
    mcp = RailsMarkup::McpServer.new(store: @store, input: StringIO.new, output: @output)
    assert_equal "/admin/annotations", mcp.send(:mount_path)
  end

  def test_mount_path_reads_from_env
    ENV["RAILS_MARKUP_MOUNT_PATH"] = "/feedback"
    mcp = RailsMarkup::McpServer.new(store: @store, input: StringIO.new, output: @output)
    assert_equal "/feedback", mcp.send(:mount_path)
  ensure
    ENV.delete("RAILS_MARKUP_MOUNT_PATH")
  end

  def test_external_api_base_builds_correct_path
    mcp = RailsMarkup::McpServer.new(store: @store, input: StringIO.new, output: @output)
    assert_equal "http://localhost:3000/admin/annotations/external",
      mcp.send(:external_api_base, "http://localhost:3000")
  end

  def test_external_api_base_with_custom_mount
    ENV["RAILS_MARKUP_MOUNT_PATH"] = "/feedback"
    mcp = RailsMarkup::McpServer.new(store: @store, input: StringIO.new, output: @output)
    assert_equal "https://myapp.com/feedback/external",
      mcp.send(:external_api_base, "https://myapp.com")
  ensure
    ENV.delete("RAILS_MARKUP_MOUNT_PATH")
  end

  def test_config_falls_back_to_mcp_json
    dir = Dir.mktmpdir
    mcp_json = File.join(dir, ".mcp.json")
    File.write(mcp_json, JSON.generate({
      "mcpServers" => {
        "rails-markup" => {
          "env" => {
            "RAILS_MARKUP_PROD_URL" => "https://fallback.test",
            "RAILS_MARKUP_PROD_TOKEN" => "fallback_token",
            "RAILS_MARKUP_DEV_URL" => "http://dev.test:3000",
            "RAILS_MARKUP_MOUNT_PATH" => "/feedback"
          }
        }
      }
    }))

    mcp = RailsMarkup::McpServer.new(store: @store, input: StringIO.new, output: @output, dir: dir)
    assert_equal "https://fallback.test", mcp.send(:prod_url)
    assert_equal "fallback_token", mcp.send(:prod_token)
    assert_equal "http://dev.test:3000", mcp.send(:dev_url)
    assert_equal "/feedback", mcp.send(:mount_path)
  ensure
    FileUtils.remove_entry(dir)
  end

  def test_env_vars_override_mcp_json
    dir = Dir.mktmpdir
    mcp_json = File.join(dir, ".mcp.json")
    File.write(mcp_json, JSON.generate({
      "mcpServers" => {
        "rails-markup" => {
          "env" => { "RAILS_MARKUP_PROD_URL" => "https://fallback.test" }
        }
      }
    }))

    ENV["RAILS_MARKUP_PROD_URL"] = "https://env-override.test"
    mcp = RailsMarkup::McpServer.new(store: @store, input: StringIO.new, output: @output, dir: dir)
    assert_equal "https://env-override.test", mcp.send(:prod_url)
  ensure
    ENV.delete("RAILS_MARKUP_PROD_URL")
    FileUtils.remove_entry(dir)
  end

  private

  def jsonrpc_request(id, method, params = nil)
    msg = { jsonrpc: "2.0", id: id, method: method }
    msg[:params] = params if params
    "#{msg.to_json}\n"
  end

  def parse_output
    JSON.parse(@output.string.lines.first)
  end

  # Call a tool and return the parsed content
  def call_tool(name, **args)
    response = call_tool_response(name, **args)
    JSON.parse(response["result"]["content"].first["text"])
  end

  def call_tool_response(name, **args)
    @output = StringIO.new
    input = StringIO.new(jsonrpc_request(1, "tools/call", { name: name, arguments: args.transform_keys(&:to_s) }))
    mcp = RailsMarkup::McpServer.new(store: @store, input: input, output: @output)
    mcp.start
    parse_output
  end

  def create_test_annotation
    session = @store.create_session(url: "http://example.com")
    @store.create_annotation(session_id: session.id, target: "div", content: "fix this")
  end

  def capture_stderr
    old_stderr = $stderr
    $stderr = StringIO.new
    yield
    $stderr.string
  ensure
    $stderr = old_stderr
  end
end

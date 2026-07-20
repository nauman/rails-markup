# frozen_string_literal: true

require_relative "test_helper"
require "stringio"
require "openssl"

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

  def test_unknown_argument_error_never_reflects_caller_controlled_key_names
    malicious_key = "private annotation content bearer-secret"
    response = nil
    stderr = capture_stderr do
      response = raw_tool_call_response(
        "rails_markup_read",
        { "resource" => "pending", malicious_key => "private request payload" }
      )
    end

    combined = response.to_json + stderr
    assert_equal true, response.dig("result", "isError")
    assert_match(/Remove unsupported arguments\./, response.dig("result", "content", 0, "text"))
    refute_includes combined, malicious_key
    refute_includes combined, "private request payload"
    refute_includes combined, "bearer-secret"
  end

  def test_explicit_non_object_tool_arguments_are_rejected_in_band
    [false, nil, [], "scalar", 123].each do |arguments|
      response = raw_tool_call_response("rails_markup_read", arguments)
      assert_equal true, response.dig("result", "isError"), arguments.inspect
      assert_match(/arguments must be an object/i, response.dig("result", "content", 0, "text"))
    end
  end

  def test_explicit_false_watch_arguments_do_not_start_watch
    subscribed = false
    @store.define_singleton_method(:subscribe) do |*args|
      subscribed = true
      raise "watch should not start"
    end

    response = raw_tool_call_response("rails_markup_watch", false)
    assert_equal true, response.dig("result", "isError")
    assert_match(/arguments must be an object/i, response.dig("result", "content", 0, "text"))
    refute subscribed
  end

  def test_environment_defaults_only_when_omitted
    assert_equal [], call_tool("rails_markup_read", resource: "pending")

    [false, nil].each do |environment|
      response = raw_tool_call_response(
        "rails_markup_read",
        { "resource" => "pending", "environment" => environment }
      )
      assert_equal true, response.dig("result", "isError"), environment.inspect
      assert_match(/environment must be development or production/i, response.dig("result", "content", 0, "text"))
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
    result = nil
    capture_stderr { result = call_tool("rails_markup_watch_annotations", timeoutSeconds: 0) }
    assert_equal [], result
  end

  def test_watch_unsubscribes_exact_subscription_when_timing_loop_raises
    subscription = Object.new
    unsubscribed = []
    @store.define_singleton_method(:subscribe) { |_session_id, &block| subscription }
    @store.define_singleton_method(:unsubscribe) { |candidate| unsubscribed << candidate }
    input = StringIO.new(jsonrpc_request(1, "tools/call", {
      name: "rails_markup_watch", arguments: { timeoutSeconds: 1 }
    }))
    mcp = RailsMarkup::McpServer.new(store: @store, input: input, output: @output)
    mcp.define_singleton_method(:sleep) { |_seconds| raise Timeout::Error, "timing failure" }

    mcp.start

    response = parse_output
    assert_equal true, response.dig("result", "isError")
    assert_match(/timed out/i, response.dig("result", "content", 0, "text"))
    assert_equal 1, unsubscribed.size
    assert_same subscription, unsubscribed.first
  end

  def test_watch_does_not_unsubscribe_when_subscription_fails
    unsubscribed = []
    @store.define_singleton_method(:subscribe) { |_session_id, &block| raise SocketError, "subscribe failed" }
    @store.define_singleton_method(:unsubscribe) { |candidate| unsubscribed << candidate }
    input = StringIO.new(jsonrpc_request(1, "tools/call", {
      name: "rails_markup_watch", arguments: { timeoutSeconds: 0 }
    }))

    RailsMarkup::McpServer.new(store: @store, input: input, output: @output).start

    assert_equal true, parse_output.dig("result", "isError")
    assert_empty unsubscribed
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

  def test_legacy_reply_and_dismiss_production_inject_environment
    annotation = create_test_annotation
    reply = nil
    dismiss = nil
    capture_stderr do
      reply = call_tool("rails_markup_reply_production", annotationId: annotation.id, message: "test")
      dismiss = call_tool("rails_markup_dismiss_production", annotationId: annotation.id, reason: "test")
    end
    assert_match(/No production URL/, reply["error"])
    assert_match(/No production URL/, dismiss["error"])
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

  def test_unknown_json_rpc_method_remains_a_protocol_error
    input = StringIO.new(jsonrpc_request(1, "unsupported/method"))
    RailsMarkup::McpServer.new(store: @store, input: input, output: @output).start

    response = parse_output
    assert_equal(-32601, response.dig("error", "code"))
    refute response.key?("result")
  end

  def test_invalid_json_rpc_request_returns_protocol_error_and_loop_continues
    input = StringIO.new([
      JSON.generate({ jsonrpc: "2.0", id: 1, method: 123 }), "\n",
      jsonrpc_request(2, "ping")
    ].join)
    RailsMarkup::McpServer.new(store: @store, input: input, output: @output).start

    responses = output_responses
    assert_equal(-32600, responses.first.dig("error", "code"))
    assert_equal({}, responses.last["result"])
  end

  def test_malformed_incoming_json_emits_parse_error_and_loop_continues
    input = StringIO.new("{not-json\n#{jsonrpc_request(2, "ping")}")
    RailsMarkup::McpServer.new(store: @store, input: input, output: @output).start

    responses = output_responses
    assert_equal(-32700, responses.first.dig("error", "code"))
    assert_equal "Parse error", responses.first.dig("error", "message")
    assert_equal({}, responses.last["result"])
  end

  def test_remote_failures_are_in_band_and_loop_continues
    failures = [
      JSON::ParserError.new("response contained sensitive annotation text"),
      URI::InvalidURIError.new("https://user:password@example.test?token=sensitive"),
      Timeout::Error.new("request body was sensitive"),
      SocketError.new("configured-secret"),
      Errno::ECONNREFUSED.new("configured-secret"),
      OpenSSL::SSL::SSLError.new("configured-secret"),
      Net::HTTPBadResponse.new("configured-secret")
    ]

    failures.each do |failure|
      responses, stderr = production_read_then_ping do |mcp|
        mcp.define_singleton_method(:http_get) { |*| raise failure }
      end
      assert_equal true, responses.first.dig("result", "isError"), failure.class.name
      assert_equal({}, responses.last["result"], failure.class.name)
      combined = responses.to_json + stderr
      refute_includes combined, "configured-secret"
      refute_includes combined, "sensitive annotation text"
      refute_includes combined, "request body was sensitive"
      refute_includes combined, "user:password"
      refute_includes combined, "token=sensitive"
    end
  end

  def test_invalid_remote_json_is_in_band_and_loop_continues
    responses, = production_read_then_ping do |mcp|
      response = fake_http_response("200", "not-json-sensitive-annotation")
      mcp.define_singleton_method(:http_get) { |*| response }
    end

    assert_equal true, responses.first.dig("result", "isError")
    assert_match(/invalid JSON/i, responses.first.dig("result", "content", 0, "text"))
    assert_equal({}, responses.last["result"])
    refute_includes responses.to_json, "sensitive-annotation"
  end

  def test_non_success_remote_responses_are_in_band_redacted_and_loop_continues
    { "401" => /authentication/i, "503" => /HTTP 503/ }.each do |code, message|
      responses, stderr = production_read_then_ping do |mcp|
        response = fake_http_response(code, "sensitive annotation and request body")
        mcp.define_singleton_method(:http_get) { |*| response }
      end

      assert_equal true, responses.first.dig("result", "isError")
      assert_match message, responses.first.dig("result", "content", 0, "text")
      assert_equal({}, responses.last["result"])
      refute_includes responses.to_json + stderr, "sensitive annotation"
    end
  end

  def test_validation_and_config_errors_do_not_echo_secrets_or_caller_content
    ENV["RAILS_MARKUP_PROD_URL"] = "https://url-user:url-password@example.test?token=url-secret"
    ENV["RAILS_MARKUP_PROD_TOKEN"] = "bearer-secret"
    response = nil
    config_response = nil
    stderr = capture_stderr do
      response = call_tool_response(
        "rails_markup_reply",
        annotationId: "123",
        message: "private annotation content",
        token: "caller-secret",
        environment: "production"
      )
      config_response = call_tool_response("rails_markup_read", resource: "pending", environment: "production")
    end

    combined = response.to_json + config_response.to_json + stderr
    assert_equal true, response.dig("result", "isError")
    assert_equal true, config_response.dig("result", "isError")
    %w[url-user url-password url-secret bearer-secret caller-secret private].each do |secret|
      refute_includes combined, secret
    end
  ensure
    ENV.delete("RAILS_MARKUP_PROD_URL")
    ENV.delete("RAILS_MARKUP_PROD_TOKEN")
  end

  def test_invalid_argument_types_and_watch_bounds_are_in_band
    calls = [
      ["rails_markup_read", { resource: "session", sessionId: 123 }],
      ["rails_markup_read", { resource: "pending", sessionId: [] }],
      ["rails_markup_watch", { timeoutSeconds: "soon" }],
      ["rails_markup_watch", { timeoutSeconds: 301 }],
      ["rails_markup_watch", { batchWindowSeconds: -1 }],
      ["rails_markup_transition", { action: "resolve", annotationId: 123 }],
      ["rails_markup_reply", { annotationId: "123", message: [] }]
    ]

    calls.each do |name, arguments|
      response = call_tool_response(name, **arguments)
      assert_equal true, response.dig("result", "isError"), "expected #{name} to validate types and bounds"
    end
  end

  def test_invalid_configuration_is_in_band_and_loop_continues
    dir = Dir.mktmpdir
    File.write(File.join(dir, ".mcp.json"), "{invalid-config")
    input = StringIO.new([
      jsonrpc_request(1, "tools/call", {
        name: "rails_markup_read", arguments: { resource: "pending", environment: "production" }
      }),
      jsonrpc_request(2, "ping")
    ].join)
    RailsMarkup::McpServer.new(store: @store, input: input, output: @output, dir: dir).start

    responses = output_responses
    assert_equal true, responses.first.dig("result", "isError")
    assert_match(/configuration is invalid/i, responses.first.dig("result", "content", 0, "text"))
    assert_equal({}, responses.last["result"])
  ensure
    FileUtils.remove_entry(dir) if dir
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

  def test_external_api_base_preserves_configured_base_path
    mcp = RailsMarkup::McpServer.new(store: @store, input: StringIO.new, output: @output)
    assert_equal "https://example.test/my-app/admin/annotations/external",
      mcp.send(:external_api_base, "https://example.test/my-app")
  end

  def test_external_api_url_cannot_discard_or_escape_mount
    mcp = RailsMarkup::McpServer.new(store: @store, input: StringIO.new, output: @output)
    assert_equal "https://example.test/my-app/admin/annotations/external/abc/resolve",
      mcp.send(:external_api_url, "https://example.test/my-app", "abc", "resolve")

    assert_raises(RailsMarkup::McpServer::TargetError) do
      mcp.send(:external_api_url, "https://example.test/my-app", "../outside")
    end
    ENV["RAILS_MARKUP_MOUNT_PATH"] = "/../../outside"
    assert_raises(RailsMarkup::McpServer::TargetError) do
      mcp.send(:external_api_base, "https://example.test/my-app")
    end
  ensure
    ENV.delete("RAILS_MARKUP_MOUNT_PATH")
  end

  def test_production_target_requires_configured_https
    %w[http://example.test ftp://example.test].each do |url|
      ENV["RAILS_MARKUP_PROD_URL"] = url
      response = call_tool_response("rails_markup_read", resource: "pending", environment: "production")
      assert_equal true, response.dig("result", "isError")
      assert_match(/configured production URL must use HTTPS/i, response.dig("result", "content", 0, "text"))
    end
  ensure
    ENV.delete("RAILS_MARKUP_PROD_URL")
  end

  def test_production_target_requires_configured_token
    ENV["RAILS_MARKUP_PROD_URL"] = "https://configured.test"
    response = call_tool_response("rails_markup_read", resource: "pending", environment: "production")

    assert_equal true, response.dig("result", "isError")
    assert_match(/production token is not configured/i, response.dig("result", "content", 0, "text"))
  ensure
    ENV.delete("RAILS_MARKUP_PROD_URL")
  end

  def test_watch_rejects_production_targeting
    response = call_tool_response("rails_markup_watch", environment: "production")
    assert_equal true, response.dig("result", "isError")
  end

  def test_development_http_accepts_only_loopback_hosts
    accepted = %w[http://localhost:3000 http://127.0.0.42:3000 http://[::1]:3000]
    rejected = %w[http://example.test:3000 http://192.168.1.5:3000]
    mcp = RailsMarkup::McpServer.new(store: @store, input: StringIO.new, output: @output)

    accepted.each { |url| assert_equal url, mcp.send(:validated_target_url, url, environment: "development").to_s }
    rejected.each do |url|
      assert_raises(RailsMarkup::McpServer::TargetError) do
        mcp.send(:validated_target_url, url, environment: "development")
      end
    end
    assert_equal "https://staging.example.test/base",
      mcp.send(:validated_target_url, "https://staging.example.test/base", environment: "development").to_s
  end

  def test_configured_targets_reject_userinfo_query_and_fragment
    urls = [
      "https://user:password@example.test",
      "https://example.test?token=secret",
      "https://example.test/path#fragment"
    ]
    mcp = RailsMarkup::McpServer.new(store: @store, input: StringIO.new, output: @output)

    urls.each do |url|
      assert_raises(RailsMarkup::McpServer::TargetError) do
        mcp.send(:validated_target_url, url, environment: "production")
      end
    end
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

  def output_responses
    @output.string.lines.map { |line| JSON.parse(line) }
  end

  # Call a tool and return the parsed content
  def call_tool(name, **args)
    response = call_tool_response(name, **args)
    JSON.parse(response["result"]["content"].first["text"])
  end

  def call_tool_response(name, **args)
    raw_tool_call_response(name, args.transform_keys(&:to_s))
  end

  def raw_tool_call_response(name, arguments = :omitted)
    @output = StringIO.new
    params = { name: name }
    params[:arguments] = arguments unless arguments == :omitted
    input = StringIO.new(jsonrpc_request(1, "tools/call", params))
    mcp = RailsMarkup::McpServer.new(store: @store, input: input, output: @output)
    mcp.start
    parse_output
  end

  def create_test_annotation
    session = @store.create_session(url: "http://example.com")
    @store.create_annotation(session_id: session.id, target: "div", content: "fix this")
  end

  def production_read_then_ping
    ENV["RAILS_MARKUP_PROD_URL"] = "https://configured.test/base"
    ENV["RAILS_MARKUP_PROD_TOKEN"] = "configured-test-token"
    @output = StringIO.new
    input = StringIO.new([
      jsonrpc_request(1, "tools/call", {
        name: "rails_markup_read", arguments: { resource: "pending", environment: "production" }
      }),
      jsonrpc_request(2, "ping")
    ].join)
    mcp = RailsMarkup::McpServer.new(store: @store, input: input, output: @output)
    yield mcp
    stderr = capture_stderr { mcp.start }
    [output_responses, stderr]
  ensure
    ENV.delete("RAILS_MARKUP_PROD_URL")
    ENV.delete("RAILS_MARKUP_PROD_TOKEN")
  end

  def fake_http_response(code, body)
    response = Struct.new(:code, :body).new(code, body)
    response.define_singleton_method(:is_a?) do |klass|
      klass == Net::HTTPSuccess && code.start_with?("2")
    end
    response
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

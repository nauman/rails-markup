# frozen_string_literal: true

require_relative "test_helper"
require "stringio"

class McpServerTest < Minitest::Test
  def setup
    @store  = RailsMarkup::Store.new
    @output = StringIO.new
  end

  def test_initialize_response
    input = StringIO.new(jsonrpc_request(1, "initialize", { protocolVersion: "2024-11-05" }))
    mcp = RailsMarkup::McpServer.new(store: @store, input: input, output: @output)
    mcp.start

    response = parse_output
    assert_equal "2.0", response["jsonrpc"]
    assert_equal 1, response["id"]
    assert_equal "rails-markup", response["result"]["serverInfo"]["name"]
  end

  def test_tools_list
    input = StringIO.new(jsonrpc_request(1, "tools/list"))
    mcp = RailsMarkup::McpServer.new(store: @store, input: input, output: @output)
    mcp.start

    response = parse_output
    tools = response["result"]["tools"]
    assert_equal 13, tools.size
    assert_equal "rails_markup_list_sessions", tools.first["name"]
  end

  def test_list_sessions_empty
    input = StringIO.new(jsonrpc_request(1, "tools/call", { name: "rails_markup_list_sessions", arguments: {} }))
    mcp = RailsMarkup::McpServer.new(store: @store, input: input, output: @output)
    mcp.start

    response = parse_output
    content = JSON.parse(response["result"]["content"].first["text"])
    assert_equal [], content
  end

  def test_list_sessions_with_data
    @store.create_session(url: "http://example.com")
    input = StringIO.new(jsonrpc_request(1, "tools/call", { name: "rails_markup_list_sessions", arguments: {} }))
    mcp = RailsMarkup::McpServer.new(store: @store, input: input, output: @output)
    mcp.start

    response = parse_output
    content = JSON.parse(response["result"]["content"].first["text"])
    assert_equal 1, content.size
  end

  def test_get_session
    session = @store.create_session(url: "http://example.com")
    input = StringIO.new(jsonrpc_request(1, "tools/call", {
      name: "rails_markup_get_session", arguments: { sessionId: session.id }
    }))
    mcp = RailsMarkup::McpServer.new(store: @store, input: input, output: @output)
    mcp.start

    response = parse_output
    content = JSON.parse(response["result"]["content"].first["text"])
    assert_equal session.id, content["id"]
  end

  def test_get_all_pending
    session = @store.create_session(url: "http://example.com")
    @store.create_annotation(session_id: session.id, target: "div", content: "fix this")
    input = StringIO.new(jsonrpc_request(1, "tools/call", {
      name: "rails_markup_get_all_pending", arguments: {}
    }))
    mcp = RailsMarkup::McpServer.new(store: @store, input: input, output: @output)
    mcp.start

    response = parse_output
    content = JSON.parse(response["result"]["content"].first["text"])
    assert_equal 1, content.size
    assert_equal "fix this", content.first["content"]
  end

  def test_resolve_annotation
    session = @store.create_session(url: "http://example.com")
    ann = @store.create_annotation(session_id: session.id, target: "div", content: "fix this")
    input = StringIO.new(jsonrpc_request(1, "tools/call", {
      name: "rails_markup_resolve", arguments: { annotationId: ann.id, summary: "Fixed padding" }
    }))
    mcp = RailsMarkup::McpServer.new(store: @store, input: input, output: @output)
    mcp.start

    response = parse_output
    content = JSON.parse(response["result"]["content"].first["text"])
    assert_equal "resolved", content["status"]
  end

  def test_dismiss_annotation
    session = @store.create_session(url: "http://example.com")
    ann = @store.create_annotation(session_id: session.id, target: "div", content: "change this")
    input = StringIO.new(jsonrpc_request(1, "tools/call", {
      name: "rails_markup_dismiss", arguments: { annotationId: ann.id, reason: "Working as intended" }
    }))
    mcp = RailsMarkup::McpServer.new(store: @store, input: input, output: @output)
    mcp.start

    response = parse_output
    content = JSON.parse(response["result"]["content"].first["text"])
    assert_equal "dismissed", content["status"]
  end

  def test_reply_to_annotation
    session = @store.create_session(url: "http://example.com")
    ann = @store.create_annotation(session_id: session.id, target: "div", content: "fix this")
    input = StringIO.new(jsonrpc_request(1, "tools/call", {
      name: "rails_markup_reply", arguments: { annotationId: ann.id, message: "Can you clarify?" }
    }))
    mcp = RailsMarkup::McpServer.new(store: @store, input: input, output: @output)
    mcp.start

    response = parse_output
    content = JSON.parse(response["result"]["content"].first["text"])
    assert_equal 1, content["thread"].size
    assert_equal "Can you clarify?", content["thread"].first["message"]
  end

  def test_acknowledge_annotation
    session = @store.create_session(url: "http://example.com")
    ann = @store.create_annotation(session_id: session.id, target: "div", content: "note")
    input = StringIO.new(jsonrpc_request(1, "tools/call", {
      name: "rails_markup_acknowledge", arguments: { annotationId: ann.id }
    }))
    mcp = RailsMarkup::McpServer.new(store: @store, input: input, output: @output)
    mcp.start

    response = parse_output
    content = JSON.parse(response["result"]["content"].first["text"])
    assert_equal "acknowledged", content["status"]
  end

  def test_unknown_tool
    input = StringIO.new(jsonrpc_request(1, "tools/call", {
      name: "rails_markup_nonexistent", arguments: {}
    }))
    mcp = RailsMarkup::McpServer.new(store: @store, input: input, output: @output)
    mcp.start

    response = parse_output
    assert response["error"]
    assert_equal(-32602, response["error"]["code"])
  end

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

  def test_fetch_production_without_url_returns_error
    input = StringIO.new(jsonrpc_request(1, "tools/call", {
      name: "rails_markup_fetch_production", arguments: {}
    }))
    mcp = RailsMarkup::McpServer.new(store: @store, input: input, output: @output)
    mcp.start

    response = parse_output
    content = JSON.parse(response["result"]["content"].first["text"])
    assert_match(/No base URL/, content["error"])
    assert_match(/bin\/markup configure/, content["error"])
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
end

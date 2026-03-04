# frozen_string_literal: true

require "json"

module RailsMarkup
  # MCP (Model Context Protocol) server speaking JSON-RPC 2.0 over stdio.
  # Exposes 9 tools for AI agents to read and act on browser annotations.
  class McpServer
    TOOLS = [
      {
        name: "rails_markup_list_sessions",
        description: "List all active annotation sessions",
        inputSchema: { type: "object", properties: {}, required: [] }
      },
      {
        name: "rails_markup_get_session",
        description: "Get a session with all its annotations",
        inputSchema: {
          type: "object",
          properties: { sessionId: { type: "string", description: "The session ID to get" } },
          required: ["sessionId"]
        }
      },
      {
        name: "rails_markup_get_pending",
        description: "Get all pending (unacknowledged) annotations for a session",
        inputSchema: {
          type: "object",
          properties: { sessionId: { type: "string", description: "The session ID" } },
          required: ["sessionId"]
        }
      },
      {
        name: "rails_markup_get_all_pending",
        description: "Get all pending annotations across ALL sessions",
        inputSchema: { type: "object", properties: {}, required: [] }
      },
      {
        name: "rails_markup_watch_annotations",
        description: "Block until new annotations appear, then return them as a batch. Use in a loop for hands-free processing.",
        inputSchema: {
          type: "object",
          properties: {
            sessionId: { type: "string", description: "Optional session ID to filter" },
            timeoutSeconds: { type: "number", description: "Max seconds to wait (default: 120, max: 300)" },
            batchWindowSeconds: { type: "number", description: "Seconds to wait after first annotation before returning batch (default: 10, max: 60)" }
          },
          required: []
        }
      },
      {
        name: "rails_markup_acknowledge",
        description: "Mark an annotation as acknowledged",
        inputSchema: {
          type: "object",
          properties: { annotationId: { type: "string", description: "The annotation ID" } },
          required: ["annotationId"]
        }
      },
      {
        name: "rails_markup_resolve",
        description: "Mark an annotation as resolved with an optional summary",
        inputSchema: {
          type: "object",
          properties: {
            annotationId: { type: "string", description: "The annotation ID" },
            summary: { type: "string", description: "Optional summary of how it was resolved" }
          },
          required: ["annotationId"]
        }
      },
      {
        name: "rails_markup_dismiss",
        description: "Dismiss an annotation with a reason",
        inputSchema: {
          type: "object",
          properties: {
            annotationId: { type: "string", description: "The annotation ID" },
            reason: { type: "string", description: "Reason for dismissing" }
          },
          required: ["annotationId"]
        }
      },
      {
        name: "rails_markup_reply",
        description: "Add a reply to an annotation's thread",
        inputSchema: {
          type: "object",
          properties: {
            annotationId: { type: "string", description: "The annotation ID" },
            message: { type: "string", description: "The reply message" }
          },
          required: ["annotationId", "message"]
        }
      }
    ].freeze

    def initialize(store:, input: $stdin, output: $stdout)
      @store  = store
      @input  = input
      @output = output
    end

    def start
      @input.each_line do |line|
        line = line.strip
        next if line.empty?

        request = JSON.parse(line)
        response = handle_request(request)
        write_response(response) if response
      rescue JSON::ParserError => e
        write_response(error_response(nil, -32700, "Parse error: #{e.message}"))
      end
    end

    private

    def handle_request(request)
      id     = request["id"]
      method = request["method"]
      params = request["params"] || {}

      case method
      when "initialize"
        result_response(id, {
          protocolVersion: "2024-11-05",
          capabilities: { tools: {} },
          serverInfo: { name: "rails-markup", version: RailsMarkup::VERSION }
        })
      when "notifications/initialized"
        nil # No response for notifications
      when "tools/list"
        result_response(id, { tools: TOOLS })
      when "tools/call"
        handle_tool_call(id, params["name"], params["arguments"] || {})
      when "ping"
        result_response(id, {})
      else
        error_response(id, -32601, "Method not found: #{method}")
      end
    end

    def handle_tool_call(id, name, args)
      result = case name
               when "rails_markup_list_sessions"
                 sessions = @store.list_sessions
                 sessions.map { |s| @store.serialize_session(s) }
               when "rails_markup_get_session"
                 session = @store.get_session(args["sessionId"])
                 session ? @store.serialize_session(session) : { error: "Session not found" }
               when "rails_markup_get_pending"
                 pending = @store.pending_for_session(args["sessionId"])
                 pending.map { |a| @store.serialize_annotation(a) }
               when "rails_markup_get_all_pending"
                 pending = @store.all_pending
                 pending.map { |a| @store.serialize_annotation(a) }
               when "rails_markup_watch_annotations"
                 handle_watch(args)
               when "rails_markup_acknowledge"
                 ann = @store.acknowledge(args["annotationId"])
                 ann ? @store.serialize_annotation(ann) : { error: "Annotation not found" }
               when "rails_markup_resolve"
                 ann = @store.resolve(args["annotationId"], summary: args["summary"])
                 ann ? @store.serialize_annotation(ann) : { error: "Annotation not found" }
               when "rails_markup_dismiss"
                 ann = @store.dismiss(args["annotationId"], reason: args["reason"])
                 ann ? @store.serialize_annotation(ann) : { error: "Annotation not found" }
               when "rails_markup_reply"
                 ann = @store.reply(args["annotationId"], message: args["message"])
                 ann ? @store.serialize_annotation(ann) : { error: "Annotation not found" }
               else
                 return error_response(id, -32602, "Unknown tool: #{name}")
               end

      content = [{ type: "text", text: result.to_json }]
      result_response(id, { content: content })
    end

    def handle_watch(args)
      timeout = [args["timeoutSeconds"]&.to_i || 120, 300].min
      batch_window = [args["batchWindowSeconds"]&.to_i || 10, 60].min
      session_id = args["sessionId"]

      batch = []
      first_received = false
      batch_deadline = nil

      sub = @store.subscribe(session_id) do |data|
        next unless data[:type] == "annotation_created"

        batch << data[:annotation]
        unless first_received
          first_received = true
          batch_deadline = Time.now + batch_window
        end
      end

      deadline = Time.now + timeout
      loop do
        break if Time.now >= deadline
        break if first_received && Time.now >= batch_deadline

        sleep 0.5
      end

      @store.unsubscribe(sub)
      batch
    end

    def result_response(id, result)
      { jsonrpc: "2.0", id: id, result: result }
    end

    def error_response(id, code, message)
      { jsonrpc: "2.0", id: id, error: { code: code, message: message } }
    end

    def write_response(response)
      @output.puts(response.to_json)
      @output.flush
    end
  end
end

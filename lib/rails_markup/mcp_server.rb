# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module RailsMarkup
  # MCP (Model Context Protocol) server speaking JSON-RPC 2.0 over stdio.
  # Exposes 13 tools for AI agents to read and act on browser annotations
  # (9 local dev tools + 4 production feedback tools).
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
      },
      # -- Production feedback tools --
      {
        name: "rails_markup_fetch_production",
        description: "Fetch all pending annotations from the production app. Returns annotations submitted via the admin feedback toolbar.",
        inputSchema: {
          type: "object",
          properties: {
            baseUrl: { type: "string", description: "Production base URL (default: env RAILS_MARKUP_PROD_URL)" },
            token: { type: "string", description: "Internal API token (default: env RAILS_MARKUP_PROD_TOKEN)" },
            markAcknowledged: { type: "boolean", description: "Acknowledge each annotation after fetching (default: true)" }
          },
          required: []
        }
      },
      {
        name: "rails_markup_resolve_production",
        description: "Resolve a production annotation with a summary of what was fixed",
        inputSchema: {
          type: "object",
          properties: {
            annotationId: { type: "string", description: "The annotation ID" },
            summary: { type: "string", description: "Summary of how it was resolved" },
            baseUrl: { type: "string", description: "Production base URL (default: env RAILS_MARKUP_PROD_URL)" },
            token: { type: "string", description: "Internal API token (default: env RAILS_MARKUP_PROD_TOKEN)" }
          },
          required: ["annotationId"]
        }
      },
      {
        name: "rails_markup_dismiss_production",
        description: "Dismiss a production annotation with a reason",
        inputSchema: {
          type: "object",
          properties: {
            annotationId: { type: "string", description: "The annotation ID" },
            reason: { type: "string", description: "Reason for dismissing" },
            baseUrl: { type: "string", description: "Production base URL (default: env RAILS_MARKUP_PROD_URL)" },
            token: { type: "string", description: "Internal API token (default: env RAILS_MARKUP_PROD_TOKEN)" }
          },
          required: ["annotationId"]
        }
      },
      {
        name: "rails_markup_reply_production",
        description: "Reply to a production annotation thread",
        inputSchema: {
          type: "object",
          properties: {
            annotationId: { type: "string", description: "The annotation ID" },
            message: { type: "string", description: "The reply message" },
            baseUrl: { type: "string", description: "Production base URL (default: env RAILS_MARKUP_PROD_URL)" },
            token: { type: "string", description: "Internal API token (default: env RAILS_MARKUP_PROD_TOKEN)" }
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
               when "rails_markup_fetch_production"
                 handle_fetch_production(args)
               when "rails_markup_resolve_production"
                 handle_production_action(args, "resolve", summary: args["summary"])
               when "rails_markup_dismiss_production"
                 handle_production_action(args, "dismiss", reason: args["reason"])
               when "rails_markup_reply_production"
                 handle_production_action(args, "reply", message: args["message"])
               else
                 return error_response(id, -32602, "Unknown tool: #{name}")
               end

      content = [{ type: "text", text: result.to_json }]
      result_response(id, { content: content })
    end

    # -- Production API helpers --

    def prod_base_url(args)
      args["baseUrl"] || ENV["RAILS_MARKUP_PROD_URL"]
    end

    def prod_token(args)
      args["token"] || ENV["RAILS_MARKUP_PROD_TOKEN"]
    end

    def handle_fetch_production(args)
      base = prod_base_url(args)
      token = prod_token(args)
      return { error: "No base URL. Set RAILS_MARKUP_PROD_URL env var or pass baseUrl param." } unless base
      return { error: "No token. Set RAILS_MARKUP_PROD_TOKEN env var or pass token param." } unless token

      mark_acknowledged = args["markAcknowledged"] != false

      resp = prod_get("#{base}/internal/annotations/pending", token)
      return { error: "API error: #{resp.code} #{resp.body}" } unless resp.is_a?(Net::HTTPSuccess)

      data = JSON.parse(resp.body)
      annotations = data["annotations"] || []

      if mark_acknowledged && annotations.any?
        annotations.each do |ann|
          prod_patch("#{base}/internal/annotations/#{ann["id"]}/acknowledge", token)
        end
      end

      { count: annotations.size, annotations: annotations }
    end

    def handle_production_action(args, action, **params)
      base = prod_base_url(args)
      token = prod_token(args)
      annotation_id = args["annotationId"]
      return { error: "No base URL. Set RAILS_MARKUP_PROD_URL env var or pass baseUrl param." } unless base
      return { error: "No token. Set RAILS_MARKUP_PROD_TOKEN env var or pass token param." } unless token
      return { error: "No annotationId provided." } unless annotation_id

      resp = prod_patch("#{base}/internal/annotations/#{annotation_id}/#{action}", token, params)
      return { error: "API error: #{resp.code} #{resp.body}" } unless resp.is_a?(Net::HTTPSuccess)

      JSON.parse(resp.body)
    end

    def prod_get(url, token)
      uri = URI.parse(url)
      req = Net::HTTP::Get.new(uri)
      req["Authorization"] = "Bearer #{token}"
      req["Accept"] = "application/json"
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = 10
      http.read_timeout = 15
      http.request(req)
    end

    def prod_patch(url, token, params = {})
      uri = URI.parse(url)
      req = Net::HTTP::Patch.new(uri)
      req["Authorization"] = "Bearer #{token}"
      req["Content-Type"] = "application/json"
      req["Accept"] = "application/json"
      req.body = params.to_json unless params.empty?
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = 10
      http.read_timeout = 15
      http.request(req)
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

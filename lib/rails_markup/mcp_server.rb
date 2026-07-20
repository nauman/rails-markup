# frozen_string_literal: true

require "json"
require "ipaddr"
require "net/http"
require "uri"
require_relative "mcp_config"

module RailsMarkup
  # MCP (Model Context Protocol) server speaking JSON-RPC 2.0 over stdio.
  # Exposes five focused tools for AI agents to read and act on browser annotations.
  # Each tool accepts an optional `environment` param ("development"|"production")
  # to route to the correct backend (default: "development").
  #
  # Configuration (via .mcp.json env vars, set by `bin/markup configure`):
  #   RAILS_MARKUP_DEV_URL    — local Rails server URL (auto-detected on install)
  #   RAILS_MARKUP_PROD_URL   — production URL
  #   RAILS_MARKUP_PROD_TOKEN — production API token
  #   RAILS_MARKUP_MOUNT_PATH — engine mount path (default: /admin/annotations)
  class McpServer
    class TargetError < StandardError; end

    ENV_SCHEMA = {
      environment: {
        type: "string",
        enum: %w[development production],
        description: "Target environment (default: development)"
      }
    }.freeze

    TOOLS = [
      {
        name: "rails_markup_read",
        description: "Read pending annotations, sessions, one session, or one annotation without changing state.",
        inputSchema: {
          type: "object",
          properties: {
            resource: {
              type: "string",
              enum: %w[pending sessions session annotation],
              description: "Resource to read; session requires sessionId and annotation requires annotationId."
            },
            **ENV_SCHEMA,
            sessionId: { type: "string", description: "Session ID, required only when resource is session; filters pending when supplied." },
            annotationId: { type: "string", description: "Annotation ID, required only when resource is annotation." }
          },
          required: ["resource"],
          additionalProperties: false
        },
        annotations: { readOnlyHint: true, destructiveHint: false }
      },
      {
        name: "rails_markup_watch",
        description: "In development, wait for newly created annotations and return a bounded batch without changing state.",
        inputSchema: {
          type: "object",
          properties: {
            sessionId: { type: "string", description: "Optional session ID to filter" },
            timeoutSeconds: { type: "number", description: "Max seconds to wait (default: 120, max: 300)" },
            batchWindowSeconds: { type: "number", description: "Seconds to wait after first annotation before returning batch (default: 10, max: 60)" }
          },
          required: [],
          additionalProperties: false
        },
        annotations: { readOnlyHint: true, destructiveHint: false }
      },
      {
        name: "rails_markup_transition",
        description: "Acknowledge or resolve one annotation; summary is used only when resolving.",
        inputSchema: {
          type: "object",
          properties: {
            action: { type: "string", enum: %w[acknowledge resolve], description: "State transition to apply." },
            annotationId: { type: "string", description: "The annotation ID" },
            summary: { type: "string", description: "Optional resolution summary; valid only for resolve." },
            **ENV_SCHEMA
          },
          required: %w[action annotationId],
          additionalProperties: false
        },
        annotations: { readOnlyHint: false, destructiveHint: false }
      },
      {
        name: "rails_markup_reply",
        description: "Add a message to one annotation's discussion thread.",
        inputSchema: {
          type: "object",
          properties: {
            annotationId: { type: "string", description: "The annotation ID" },
            message: { type: "string", description: "Reply message" },
            **ENV_SCHEMA
          },
          required: %w[annotationId message],
          additionalProperties: false
        },
        annotations: { readOnlyHint: false, destructiveHint: false }
      },
      {
        name: "rails_markup_dismiss",
        description: "Destructively dismiss one annotation with an explicit reason.",
        inputSchema: {
          type: "object",
          properties: {
            annotationId: { type: "string", description: "The annotation ID" },
            reason: { type: "string", description: "Reason for dismissal" },
            **ENV_SCHEMA
          },
          required: %w[annotationId reason],
          additionalProperties: false
        },
        annotations: { readOnlyHint: false, destructiveHint: true }
      }
    ].freeze

    TOOL_ARGUMENTS = {
      "rails_markup_read" => %w[resource environment sessionId annotationId],
      "rails_markup_watch" => %w[sessionId timeoutSeconds batchWindowSeconds],
      "rails_markup_transition" => %w[action annotationId summary environment],
      "rails_markup_reply" => %w[annotationId message environment],
      "rails_markup_dismiss" => %w[annotationId reason environment]
    }.freeze

    # Legacy tool names → canonical handler + trusted injected args.
    # Removed after v1.3.0.
    LEGACY_ALIASES = {
      "rails_markup_sessions" => { handler: "rails_markup_read", inject: { "resource" => "sessions" } },
      "rails_markup_list_sessions" => { handler: "rails_markup_read", inject: { "resource" => "sessions" } },
      "rails_markup_session" => { handler: "rails_markup_read", inject: { "resource" => "session" } },
      "rails_markup_get_session" => { handler: "rails_markup_read", inject: { "resource" => "session" } },
      "rails_markup_pending" => { handler: "rails_markup_read", inject: { "resource" => "pending" } },
      "rails_markup_get_pending" => { handler: "rails_markup_read", inject: { "resource" => "pending" } },
      "rails_markup_get_all_pending" => { handler: "rails_markup_read", inject: { "resource" => "pending" } },
      "rails_markup_fetch_production" => {
        handler: "rails_markup_read", inject: { "resource" => "pending", "environment" => "production" }
      },
      "rails_markup_watch_annotations" => { handler: "rails_markup_watch" },
      "rails_markup_acknowledge" => { handler: "rails_markup_transition", inject: { "action" => "acknowledge" } },
      "rails_markup_resolve" => { handler: "rails_markup_transition", inject: { "action" => "resolve" } },
      "rails_markup_resolve_production" => {
        handler: "rails_markup_transition", inject: { "action" => "resolve", "environment" => "production" }
      },
      "rails_markup_reply_production" => { handler: "rails_markup_reply", inject: { "environment" => "production" } },
      "rails_markup_dismiss_production" => { handler: "rails_markup_dismiss", inject: { "environment" => "production" } }
    }.freeze

    def initialize(store:, input: $stdin, output: $stdout, dir: Dir.pwd)
      @store  = store
      @input  = input
      @output = output
      @mcp_config = McpConfig.new(dir: dir)
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

    # ── Shared config ─────────────────────────────────────────
    # ENV vars take precedence; fall back to .mcp.json values.

    def config_value(env_key)
      ENV[env_key] || @mcp_config.raw_env[env_key]
    end

    def mount_path
      config_value("RAILS_MARKUP_MOUNT_PATH") || "/admin/annotations"
    end

    def prod_url
      config_value("RAILS_MARKUP_PROD_URL")
    end

    def prod_token
      config_value("RAILS_MARKUP_PROD_TOKEN")
    end

    # Build the external API base for a given host URL.
    # All annotation access goes through the engine's external controller:
    #   {base_url}{mount_path}/external/...
    def external_api_base(base_url)
      external_api_url(base_url)
    end

    def external_api_url(base_url, *segments)
      uri = base_url.is_a?(URI::HTTP) ? base_url.dup : URI.parse(base_url)
      base_parts = safe_path_parts(uri.path, label: "configured URL path")
      mount_parts = safe_path_parts(mount_path, label: "configured mount path")
      suffix = segments.map { |segment| safe_path_segment(segment) }
      uri.path = "/#{(base_parts + mount_parts + ["external"] + suffix).join('/')}"
      uri.to_s
    rescue URI::InvalidURIError
      fail TargetError, "Configured URL is invalid. Update Rails Markup configuration."
    end

    def validated_target_url(value, environment:)
      uri = URI.parse(value.to_s)
      if environment == "production" && !(uri.is_a?(URI::HTTPS) && uri.host && !uri.host.empty?)
        fail TargetError, "Configured production URL must use HTTPS."
      end
      unless uri.is_a?(URI::HTTP) && uri.host && !uri.host.empty?
        fail TargetError, "Configured #{environment} URL must use HTTP or HTTPS."
      end
      if uri.userinfo || uri.query || uri.fragment
        fail TargetError, "Configured #{environment} URL cannot include credentials, query, or fragment."
      end
      safe_path_parts(uri.path, label: "configured URL path")

      if environment == "development" && uri.scheme == "http" && !loopback_host?(uri.host)
        fail TargetError, "Configured development HTTP URL must use a loopback host."
      end

      uri
    rescue URI::InvalidURIError
      fail TargetError, "Configured #{environment} URL is invalid."
    end

    def loopback_host?(host)
      return true if host.casecmp?("localhost")

      address = IPAddr.new(host)
      address.loopback?
    rescue IPAddr::InvalidAddressError
      false
    end

    def safe_path_parts(path, label:)
      path.to_s.split("/").reject(&:empty?).map do |part|
        decoded = URI::DEFAULT_PARSER.unescape(part)
        if %w[. ..].include?(decoded) || decoded.include?("/") || decoded.include?("\\")
          fail TargetError, "The #{label} cannot contain traversal segments."
        end
        part
      end
    end

    def safe_path_segment(segment)
      value = segment.to_s
      decoded = URI::DEFAULT_PARSER.unescape(value)
      unless value.match?(/\A[A-Za-z0-9._~-]+\z/) && !%w[. ..].include?(decoded)
        fail TargetError, "API path segment is invalid."
      end
      value
    end

    # ── JSON-RPC dispatch ─────────────────────────────────────

    def handle_request(request)
      id     = request["id"]
      method = request["method"]
      params = request["params"] || {}

      case method
      when "initialize"
        client_version = params.dig("protocolVersion")
        supported = %w[2025-06-18 2025-03-26 2024-11-05]
        negotiated = supported.include?(client_version) ? client_version : supported.first

        result_response(id, {
          protocolVersion: negotiated,
          capabilities: { tools: {} },
          serverInfo: { name: "rails-markup", title: "Rails Markup", version: RailsMarkup::VERSION }
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
      if (legacy = LEGACY_ALIASES[name])
        allowed = TOOL_ARGUMENTS.fetch(legacy[:handler]) - legacy.fetch(:inject, {}).keys
        return invalid_arguments_response(id, args.keys - allowed) unless (args.keys - allowed).empty?

        $stderr.puts "[rails-markup] DEPRECATED: #{name} → use #{legacy[:handler]}"
        name = legacy[:handler]
        args = args.merge(legacy.fetch(:inject, {}))
      end

      return tool_error_response(id, "Unknown tool. Use tools/list for supported tools.") unless TOOL_ARGUMENTS.key?(name)

      unknown = args.keys - TOOL_ARGUMENTS.fetch(name)
      return invalid_arguments_response(id, unknown) unless unknown.empty?

      if (message = validation_error(name, args))
        return tool_error_response(id, message)
      end

      result = case name
               when "rails_markup_read"
                 handle_read(args)
               when "rails_markup_watch"
                 handle_watch(args)
               when "rails_markup_transition"
                 if args["action"] == "acknowledge"
                   handle_action(args, "acknowledge")
                 else
                   handle_action(args, "resolve", summary: args["summary"])
                 end
               when "rails_markup_dismiss"
                 handle_action(args, "dismiss", reason: args["reason"])
               when "rails_markup_reply"
                 handle_action(args, "reply", message: args["message"])
               end

      content = [{ type: "text", text: result.to_json }]
      result_response(id, { content: content })
    rescue TargetError => e
      tool_error_response(id, e.message)
    end

    def validation_error(name, args)
      environment = args["environment"] || "development"
      return "environment must be development or production." unless %w[development production].include?(environment)

      case name
      when "rails_markup_read"
        resource = args["resource"]
        return "resource must be pending, sessions, session, or annotation." unless %w[pending sessions session annotation].include?(resource)
        return "sessionId is required when resource is session." if resource == "session" && blank?(args["sessionId"])
        return "annotationId is required when resource is annotation." if resource == "annotation" && blank?(args["annotationId"])
        return "annotationId is only valid when resource is annotation." if resource != "annotation" && args.key?("annotationId")
        return "sessionId is only valid for pending or session resources." if !%w[pending session].include?(resource) && args.key?("sessionId")
        if environment == "production" && %w[sessions session].include?(resource)
          return "sessions and session reads are available only in development."
        end
      when "rails_markup_transition"
        return "action must be acknowledge or resolve." unless %w[acknowledge resolve].include?(args["action"])
        return "annotationId is required." if blank?(args["annotationId"])
        return "summary is only valid for resolve." if args["action"] != "resolve" && args.key?("summary")
      when "rails_markup_reply"
        return "annotationId and message are required." if blank?(args["annotationId"]) || blank?(args["message"])
      when "rails_markup_dismiss"
        return "annotationId and reason are required." if blank?(args["annotationId"]) || blank?(args["reason"])
      end
    end

    def blank?(value)
      value.nil? || (value.respond_to?(:empty?) && value.empty?)
    end

    def invalid_arguments_response(id, unknown)
      tool_error_response(id, "Remove unsupported arguments: #{unknown.sort.join(', ')}.")
    end

    def tool_error_response(id, message)
      result_response(id, {
        content: [{ type: "text", text: { error: message }.to_json }],
        isError: true
      })
    end

    # ── Dev API proxy ─────────────────────────────────────────
    # When RAILS_MARKUP_DEV_URL is set, local tools proxy to the engine's
    # external API instead of the in-memory store. No token needed in dev.

    def dev_url
      config_value("RAILS_MARKUP_DEV_URL")
    end

    def handle_read(args)
      return handle_fetch_production(args) if args["environment"] == "production" && args["resource"] == "pending"
      if args["resource"] == "annotation" && (args["environment"] == "production" || dev_url)
        return handle_remote_annotation(args)
      end

      case args["resource"]
      when "sessions"
        handle_local_or_proxy(:list_sessions, args) do
          @store.list_sessions.map { |session| @store.serialize_session(session) }
        end
      when "session"
        handle_local_or_proxy(:get_session, args) do
          session = @store.get_session(args["sessionId"])
          session ? @store.serialize_session(session) : { error: "Session not found" }
        end
      when "annotation"
        annotation = @store.get_annotation(args["annotationId"])
        annotation ? @store.serialize_annotation(annotation) : { error: "Annotation not found" }
      when "pending"
        action = args["sessionId"] ? :get_pending : :get_all_pending
        handle_local_or_proxy(action, args) do
          pending = if args["sessionId"]
                      @store.pending_for_session(args["sessionId"])
                    else
                      @store.all_pending
                    end
          pending.map { |annotation| @store.serialize_annotation(annotation) }
        end
      end
    end

    def handle_action(args, action, **params)
      return handle_production_action(args, action, **params) if args["environment"] == "production"

      handle_local_or_proxy(action.to_sym, args) do
        annotation = @store.public_send(action, args["annotationId"], **params)
        annotation ? @store.serialize_annotation(annotation) : { error: "Annotation not found" }
      end
    end

    def handle_local_or_proxy(action, args, &fallback)
      return fallback.call unless dev_url

      target = validated_target_url(dev_url, environment: "development")

      case action
      when :list_sessions
        []
      when :get_session
        { error: "Sessions not available when using dev API proxy" }
      when :get_pending, :get_all_pending
        dev_fetch_pending(target)
      when :acknowledge
        dev_action(target, args["annotationId"], "acknowledge")
      when :resolve
        dev_action(target, args["annotationId"], "resolve", summary: args["summary"])
      when :dismiss
        dev_action(target, args["annotationId"], "dismiss", reason: args["reason"])
      when :reply
        dev_action(target, args["annotationId"], "reply", message: args["message"])
      else
        fallback.call
      end
    end

    def dev_fetch_pending(target)
      resp = http_get(external_api_url(target, "pending"))
      return { error: "Dev API error: #{resp.code} #{resp.body}" } unless resp.is_a?(Net::HTTPSuccess)

      data = JSON.parse(resp.body)
      { count: (data["annotations"] || []).size, annotations: data["annotations"] || [] }
    end

    def dev_action(target, annotation_id, action, **params)
      return { error: "No annotationId provided." } unless annotation_id

      resp = http_patch(external_api_url(target, annotation_id, action), params: params)
      return { error: "Dev API error: #{resp.code} #{resp.body}" } unless resp.is_a?(Net::HTTPSuccess)

      JSON.parse(resp.body)
    end

    # ── Production API ────────────────────────────────────────

    def handle_fetch_production(args)
      target, token = production_target
      resp = http_get(external_api_url(target, "pending"), token: token)
      return { error: "API error: #{resp.code} #{resp.body}" } unless resp.is_a?(Net::HTTPSuccess)

      data = JSON.parse(resp.body)
      annotations = data["annotations"] || []

      { count: annotations.size, annotations: annotations }
    end

    def handle_production_action(args, action, **params)
      annotation_id = args["annotationId"]
      return { error: "No annotationId provided." } unless annotation_id

      target, token = production_target
      resp = http_patch(external_api_url(target, annotation_id, action), token: token, params: params)
      return { error: "API error: #{resp.code} #{resp.body}" } unless resp.is_a?(Net::HTTPSuccess)

      JSON.parse(resp.body)
    end

    def handle_remote_annotation(args)
      if args["environment"] == "production"
        target, token = production_target
      else
        target = validated_target_url(dev_url, environment: "development")
        token = nil
      end
      resp = http_get(external_api_url(target, args["annotationId"]), token: token)
      return { error: "API error: #{resp.code} #{resp.body}" } unless resp.is_a?(Net::HTTPSuccess)

      JSON.parse(resp.body)
    end

    def production_target
      fail TargetError, "No production URL is configured. Run bin/markup configure." if blank?(prod_url)

      target = validated_target_url(prod_url, environment: "production")
      fail TargetError, "Production token is not configured. Run bin/markup configure." if blank?(prod_token)

      [target, prod_token]
    end

    # ── HTTP helpers ──────────────────────────────────────────

    def http_get(url, token: nil)
      uri = URI.parse(url)
      req = Net::HTTP::Get.new(uri)
      req["Authorization"] = "Bearer #{token}" if token
      req["Accept"] = "application/json"
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = 10
      http.read_timeout = 15
      http.request(req)
    end

    def http_patch(url, token: nil, params: {})
      uri = URI.parse(url)
      req = Net::HTTP::Patch.new(uri)
      req["Authorization"] = "Bearer #{token}" if token
      req["Content-Type"] = "application/json"
      req["Accept"] = "application/json"
      req.body = params.to_json unless params.empty?
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = 10
      http.read_timeout = 15
      http.request(req)
    end

    # ── Watch mode ────────────────────────────────────────────

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

    # ── JSON-RPC responses ────────────────────────────────────

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

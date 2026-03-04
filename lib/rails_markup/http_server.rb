# frozen_string_literal: true

require "webrick"
require "json"

module RailsMarkup
  # HTTP server providing REST API + SSE for the browser-side annotation controller.
  # Wire-compatible with Agentation's HTTP API.
  class HttpServer
    attr_reader :port, :store

    def initialize(store:, port: 4747, logger: nil)
      @store  = store
      @port   = port
      @logger = logger || WEBrick::Log.new($stderr, WEBrick::Log::WARN)
    end

    def start
      @server = WEBrick::HTTPServer.new(
        Port: @port,
        Logger: @logger,
        AccessLog: []
      )

      mount_routes

      trap("INT")  { @server.shutdown }
      trap("TERM") { @server.shutdown }

      @server.start
    end

    def shutdown
      @server&.shutdown
    end

    private

    def mount_routes
      @server.mount_proc("/health")           { |_req, res| handle_health(res) }
      @server.mount_proc("/sessions")         { |req, res| handle_sessions(req, res) }
      @server.mount_proc("/pending")          { |_req, res| handle_all_pending(res) }
    end

    # --- Health ---

    def handle_health(res)
      cors(res)
      json_response(res, { ok: true })
    end

    # --- Sessions ---

    def handle_sessions(req, res)
      cors(res)
      path = req.path

      # POST /sessions — create session
      if req.request_method == "POST" && path == "/sessions"
        body = parse_json(req)
        session = @store.create_session(url: body["url"], metadata: body["metadata"])
        json_response(res, @store.serialize_session(session), status: 201)
        return
      end

      # GET /sessions/:id — get session
      if req.request_method == "GET" && (match = path.match(%r{\A/sessions/([^/]+)\z}))
        session = @store.get_session(match[1])
        return not_found(res) unless session

        json_response(res, @store.serialize_session(session))
        return
      end

      # POST /sessions/:id/annotations — create annotation
      if req.request_method == "POST" && (match = path.match(%r{\A/sessions/([^/]+)/annotations\z}))
        body = parse_json(req)
        annotation = @store.create_annotation(
          session_id: match[1],
          target: body["target"],
          content: body["content"],
          intent: body["intent"] || "change",
          severity: body["severity"] || "suggestion",
          selected_text: body["selectedText"],
          metadata: body["metadata"]
        )
        return not_found(res) unless annotation

        json_response(res, @store.serialize_annotation(annotation), status: 201)
        return
      end

      # GET /sessions/:id/events — SSE stream
      if req.request_method == "GET" && (match = path.match(%r{\A/sessions/([^/]+)/events\z}))
        handle_sse(req, res, match[1])
        return
      end

      # OPTIONS preflight
      if req.request_method == "OPTIONS"
        cors(res)
        res.status = 204
        return
      end

      not_found(res)
    end

    # --- All pending ---

    def handle_all_pending(res)
      cors(res)
      pending = @store.all_pending
      json_response(res, pending.map { |a| @store.serialize_annotation(a) })
    end

    # --- SSE ---

    def handle_sse(_req, res, session_id)
      session = @store.get_session(session_id)
      return not_found(res) unless session

      res.status = 200
      res["Content-Type"] = "text/event-stream"
      res["Cache-Control"] = "no-cache"
      res["Connection"] = "keep-alive"
      res["Access-Control-Allow-Origin"] = "*"

      res.chunked = true
      res.body = proc do |out|
        sub = @store.subscribe(session_id) do |data|
          event_type = data[:type] || "annotation_update"
          out.write("event: #{event_type}\ndata: #{data.to_json}\n\n")
        rescue Errno::EPIPE, IOError
          @store.unsubscribe(sub)
        end

        # Keep alive — send comment every 15 seconds
        loop do
          sleep 15
          out.write(": keepalive\n\n")
        rescue Errno::EPIPE, IOError
          break
        end
      ensure
        @store.unsubscribe(sub) if defined?(sub) && sub
      end
    end

    # --- Helpers ---

    def cors(res)
      res["Access-Control-Allow-Origin"]  = "*"
      res["Access-Control-Allow-Methods"] = "GET, POST, PUT, DELETE, OPTIONS"
      res["Access-Control-Allow-Headers"] = "Content-Type, Authorization"
    end

    def json_response(res, data, status: 200)
      res.status = status
      res["Content-Type"] = "application/json"
      res.body = data.to_json
    end

    def not_found(res)
      res.status = 404
      res["Content-Type"] = "application/json"
      res.body = { error: "not_found" }.to_json
    end

    def parse_json(req)
      JSON.parse(req.body || "{}")
    rescue JSON::ParserError
      {}
    end
  end
end

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
        AccessLog: [],
        DoNotReverseLookup: true
      )

      @server.mount("/", CorsServlet, @store)

      trap("INT")  { @server.shutdown }
      trap("TERM") { @server.shutdown }

      @server.start
    end

    def shutdown
      @server&.shutdown
    end
  end

  # Single servlet handling all routes with proper CORS support.
  # WEBrick dispatches do_GET, do_POST, do_OPTIONS to us directly.
  class CorsServlet < WEBrick::HTTPServlet::AbstractServlet
    def initialize(server, store)
      super(server)
      @store = store
    end

    def do_OPTIONS(req, res)
      cors(res)
      res.status = 204
    end

    def do_GET(req, res)
      cors(res)
      route(req, res)
    end

    def do_POST(req, res)
      cors(res)
      route(req, res)
    end

    private

    def route(req, res)
      case req.path
      when "/health"
        json_response(res, { ok: true })

      when "/pending"
        pending = @store.all_pending
        json_response(res, pending.map { |a| @store.serialize_annotation(a) })

      when "/sessions"
        if req.request_method == "GET"
          sessions = @store.list_sessions
          json_response(res, sessions.map { |s| @store.serialize_session(s) })
        else
          handle_create_session(req, res)
        end

      when %r{\A/sessions/([^/]+)/annotations\z}
        handle_create_annotation(req, res, $1)

      when %r{\A/sessions/([^/]+)/events\z}
        handle_sse(req, res, $1)

      when %r{\A/sessions/([^/]+)\z}
        handle_get_session(res, $1)

      when %r{\A/annotations/([^/]+)/resolve\z}
        handle_annotation_action(req, res, $1, :resolve)

      when %r{\A/annotations/([^/]+)/dismiss\z}
        handle_annotation_action(req, res, $1, :dismiss)

      when %r{\A/annotations/([^/]+)/acknowledge\z}
        handle_annotation_action(req, res, $1, :acknowledge)

      when %r{\A/annotations/([^/]+)/reply\z}
        handle_annotation_action(req, res, $1, :reply)

      else
        not_found(res)
      end
    end

    # --- Annotation actions ---

    def handle_annotation_action(req, res, annotation_id, action)
      body = parse_json(req)
      result = case action
               when :resolve
                 @store.resolve(annotation_id, summary: body["summary"])
               when :dismiss
                 @store.dismiss(annotation_id, reason: body["reason"])
               when :acknowledge
                 @store.acknowledge(annotation_id)
               when :reply
                 @store.reply(annotation_id, message: body["message"])
               end
      return not_found(res) unless result

      json_response(res, @store.serialize_annotation(result))
    end

    # --- Sessions ---

    def handle_create_session(req, res)
      body = parse_json(req)
      session = @store.create_session(url: body["url"], metadata: body["metadata"])
      json_response(res, @store.serialize_session(session), status: 201)
    end

    def handle_get_session(res, session_id)
      session = @store.get_session(session_id)
      return not_found(res) unless session

      json_response(res, @store.serialize_session(session))
    end

    # --- Annotations ---

    def handle_create_annotation(req, res, session_id)
      body = parse_json(req)
      annotation = @store.create_annotation(
        session_id: session_id,
        target: body["target"],
        content: body["content"],
        intent: body["intent"] || "change",
        severity: body["severity"] || "suggestion",
        selected_text: body["selectedText"],
        metadata: body["metadata"]
      )
      return not_found(res) unless annotation

      json_response(res, @store.serialize_annotation(annotation), status: 201)
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

        deadline = Time.now + 1800 # 30 minutes max
        loop do
          break if Time.now >= deadline

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
      port = @server[:Port] rescue 4747
      res["Access-Control-Allow-Origin"]  = "http://localhost:#{port}"
      res["Access-Control-Allow-Methods"] = "GET, POST, OPTIONS"
      res["Access-Control-Allow-Headers"] = "Content-Type"
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

    MAX_BODY_SIZE = 1_000_000 # 1MB

    def parse_json(req)
      return {} if req.body.nil?
      return {} if req.body.bytesize > MAX_BODY_SIZE

      JSON.parse(req.body)
    rescue JSON::ParserError
      {}
    end
  end
end

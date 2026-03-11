# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

module RailsMarkup
  # Proxies store operations to an existing HTTP server.
  # Used when MCP starts but the HTTP port is already taken —
  # delegates reads/writes to the running server's HTTP API.
  class HttpStoreProxy
    def initialize(base_url: "http://localhost:4747")
      @base_url = base_url
      @uri = URI.parse(base_url)
    end

    def list_sessions
      get("/sessions") || []
    end

    def get_session(id)
      get("/sessions/#{id}")
    end

    def create_session(url:, metadata: nil)
      post("/sessions", { url: url, metadata: metadata })
    end

    def all_pending
      get("/pending") || []
    end

    def pending_for_session(session_id)
      session = get_session(session_id)
      return [] unless session

      (session["annotations"] || []).select { |a| a["status"] == "pending" }
    end

    def get_annotation(id)
      # Search all sessions for this annotation (not just pending)
      list_sessions.each do |session|
        (session["annotations"] || []).each do |ann|
          return ann if ann["id"] == id
        end
      end
      nil
    end

    def create_annotation(session_id:, target:, content:, intent: "change", severity: "suggestion", selected_text: nil, metadata: nil)
      post("/sessions/#{session_id}/annotations", {
        target: target, content: content, intent: intent,
        severity: severity, selectedText: selected_text, metadata: metadata
      })
    end

    def acknowledge(id)
      post("/annotations/#{id}/acknowledge", {})
    end

    def resolve(id, summary: nil)
      post("/annotations/#{id}/resolve", { summary: summary })
    end

    def dismiss(id, reason: nil)
      post("/annotations/#{id}/dismiss", { reason: reason })
    end

    def reply(id, message:)
      post("/annotations/#{id}/reply", { message: message })
    end

    # Proxy serialization — data is already serialized from HTTP
    def serialize_session(data)
      data
    end

    def serialize_annotation(data)
      data
    end

    # Watch not supported via HTTP proxy — return empty after timeout
    def subscribe(_session_id = nil, &_block)
      nil
    end

    def unsubscribe(_sub)
      nil
    end

    private

    def get(path)
      http = Net::HTTP.new(@uri.host, @uri.port)
      http.open_timeout = 5
      http.read_timeout = 10
      req = Net::HTTP::Get.new(path)
      resp = http.request(req)
      return nil unless resp.is_a?(Net::HTTPSuccess)

      JSON.parse(resp.body)
    rescue StandardError => e
      $stderr.puts "[rails-markup proxy] GET #{path} failed: #{e.message}"
      nil
    end

    def post(path, body)
      http = Net::HTTP.new(@uri.host, @uri.port)
      http.open_timeout = 5
      http.read_timeout = 10
      req = Net::HTTP::Post.new(path, "Content-Type" => "application/json")
      req.body = body.to_json
      resp = http.request(req)
      return nil unless resp.is_a?(Net::HTTPSuccess)

      JSON.parse(resp.body)
    rescue StandardError => e
      $stderr.puts "[rails-markup proxy] POST #{path} failed: #{e.message}"
      nil
    end
  end
end

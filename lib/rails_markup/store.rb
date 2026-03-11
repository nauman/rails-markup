# frozen_string_literal: true

require "securerandom"
require "json"

module RailsMarkup
  # In-memory store for sessions and annotations.
  # Ephemeral by design — data lives for one coding session.
  class Store
    Session    = Struct.new(:id, :url, :metadata, :created_at, :annotations, keyword_init: true)
    Annotation = Struct.new(:id, :session_id, :target, :content, :intent, :severity, :status,
                            :selected_text, :metadata, :created_at, :thread, keyword_init: true)

    MAX_SESSIONS = 100
    SESSION_TTL  = 4 * 3600 # 4 hours

    attr_reader :sessions

    def initialize
      @sessions          = {}
      @annotations_index = {} # id -> annotation (O(1) lookup)
      @subscribers       = [] # SSE callbacks: [session_id, callback]
      @mutex             = Mutex.new
    end

    # --- Sessions ---

    def create_session(url:, metadata: {})
      id = SecureRandom.hex(8)
      session = Session.new(
        id: id,
        url: url,
        metadata: metadata || {},
        created_at: Time.now.iso8601,
        annotations: []
      )
      @mutex.synchronize do
        evict_stale_sessions
        @sessions[id] = session
      end
      session
    end

    def get_session(id)
      @mutex.synchronize { @sessions[id] }
    end

    def list_sessions
      @mutex.synchronize { @sessions.values }
    end

    # --- Annotations ---

    def create_annotation(session_id:, target:, content:, intent: "change", severity: "suggestion",
                          selected_text: nil, metadata: {})
      id = SecureRandom.hex(8)
      annotation = Annotation.new(
        id: id,
        session_id: session_id,
        target: target,
        content: content,
        intent: intent,
        severity: severity,
        status: "pending",
        selected_text: selected_text,
        metadata: metadata || {},
        created_at: Time.now.iso8601,
        thread: []
      )

      # Single mutex block — no TOCTOU gap
      @mutex.synchronize do
        session = @sessions[session_id]
        return nil unless session

        session.annotations << annotation
        @annotations_index[id] = annotation
      end

      notify(session_id, type: "annotation_created", annotation: serialize_annotation(annotation))
      annotation
    end

    def get_annotation(annotation_id)
      @mutex.synchronize { @annotations_index[annotation_id] }
    end

    def pending_for_session(session_id)
      session = get_session(session_id)
      return [] unless session

      @mutex.synchronize { session.annotations.select { |a| a.status == "pending" } }
    end

    def all_pending
      @mutex.synchronize do
        @sessions.values.flat_map { |s| s.annotations.select { |a| a.status == "pending" } }
      end
    end

    # --- Status transitions ---

    def acknowledge(annotation_id)
      update_status(annotation_id, "acknowledged")
    end

    def resolve(annotation_id, summary: nil)
      ann = update_status(annotation_id, "resolved")
      return nil unless ann

      ann.thread << { role: "agent", message: summary, timestamp: Time.now.iso8601 } if summary
      notify(ann.session_id, type: "annotation_update", annotation: serialize_annotation(ann),
                             status: "resolved", summary: summary)
      ann
    end

    def dismiss(annotation_id, reason: nil)
      ann = update_status(annotation_id, "dismissed")
      return nil unless ann

      ann.thread << { role: "agent", message: reason, timestamp: Time.now.iso8601 } if reason
      notify(ann.session_id, type: "annotation_update", annotation: serialize_annotation(ann),
                             status: "dismissed", reason: reason)
      ann
    end

    def reply(annotation_id, message:)
      ann = get_annotation(annotation_id)
      return nil unless ann

      @mutex.synchronize do
        ann.thread << { role: "agent", message: message, timestamp: Time.now.iso8601 }
      end
      notify(ann.session_id, type: "annotation_update", annotation: serialize_annotation(ann),
                             status: ann.status, message: message)
      ann
    end

    # --- SSE subscriptions ---

    def subscribe(session_id, &callback)
      sub = [session_id, callback]
      @mutex.synchronize { @subscribers << sub }
      sub
    end

    def unsubscribe(sub)
      @mutex.synchronize { @subscribers.delete(sub) }
    end

    # --- Serialization ---

    def serialize_session(session)
      {
        id: session.id,
        url: session.url,
        metadata: session.metadata,
        createdAt: session.created_at,
        annotations: session.annotations.map { |a| serialize_annotation(a) }
      }
    end

    def serialize_annotation(ann)
      {
        id: ann.id,
        sessionId: ann.session_id,
        target: ann.target,
        content: ann.content,
        intent: ann.intent,
        severity: ann.severity,
        status: ann.status,
        selectedText: ann.selected_text,
        metadata: ann.metadata,
        createdAt: ann.created_at,
        thread: ann.thread
      }
    end

    private

    def update_status(annotation_id, new_status)
      ann = get_annotation(annotation_id)
      return nil unless ann

      @mutex.synchronize { ann.status = new_status }
      ann
    end

    def notify(session_id, data)
      dead = []
      @mutex.synchronize do
        @subscribers.each do |sub|
          sid, callback = sub
          next unless sid.nil? || sid == session_id

          callback.call(data)
        rescue StandardError
          dead << sub
        end
        dead.each { |s| @subscribers.delete(s) }
      end
    end

    def evict_stale_sessions
      return if @sessions.size < MAX_SESSIONS

      cutoff = (Time.now - SESSION_TTL).iso8601
      @sessions.delete_if do |_id, session|
        if session.created_at < cutoff
          session.annotations.each { |a| @annotations_index.delete(a.id) }
          true
        else
          false
        end
      end
    end
  end
end

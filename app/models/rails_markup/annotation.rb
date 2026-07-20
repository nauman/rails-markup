# frozen_string_literal: true

require "securerandom"
require "digest/sha1"

module RailsMarkup
  class Annotation < ActiveRecord::Base
    self.table_name = RailsMarkup.config.table_name

    INTENTS = %w[fix change question approve].freeze
    SEVERITIES = %w[suggestion important blocking].freeze
    STATUSES = %w[pending acknowledged resolved dismissed].freeze
    BROWSER_ATTRIBUTES = %w[content intent severity selected_text target page_url].freeze
    BROWSER_METADATA_KEYS = %w[tool url localId sessionId screenshot].freeze
    CLIENT_UUID_PATTERN = /\A[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/
    CLIENT_UUID_INPUT_PATTERN = /\A[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/i
    LEGACY_SESSION_PATTERN = /\Arm-[0-9a-f]{16}\z/i
    LEGACY_CLIENT_ID_LIMIT = 256
    LEGACY_UUID_NAMESPACE = "265e7cf0-8be6-5e21-8f31-a582cfde8646"

    # Optional user association — no FK constraint, engine doesn't know host users table
    belongs_to :user, optional: true

    # Works with both jsonb (PostgreSQL) and text (SQLite/MySQL) columns.
    attribute :target, :json, default: {}
    attribute :metadata, :json, default: {}
    attribute :thread, :json, default: []

    validates :content, presence: true, length: { maximum: 5000 }
    validates :page_url, presence: true, length: { maximum: 2048 }
    validates :selected_text, length: { maximum: 2000 }, allow_nil: true
    before_validation :ensure_client_uuid

    validates :client_uuid, presence: true, length: { maximum: 64 }, format: { with: CLIENT_UUID_PATTERN }
    validates :intent, inclusion: { in: INTENTS }
    validates :severity, inclusion: { in: SEVERITIES }
    validates :status, inclusion: { in: STATUSES }
    validate :thread_must_be_array

    def self.valid_client_uuid?(value)
      value.is_a?(String) && CLIENT_UUID_PATTERN.match?(value)
    end

    def self.normalize_client_uuid(value)
      value.downcase if value.is_a?(String) && CLIENT_UUID_INPUT_PATTERN.match?(value)
    end

    def self.legacy_client_uuid(session_id:, legacy_client_id:)
      session_id = session_id.to_s
      legacy_client_id = legacy_client_id.to_s
      unless LEGACY_SESSION_PATTERN.match?(session_id) && legacy_client_id.present? && legacy_client_id.bytesize <= LEGACY_CLIENT_ID_LIMIT
        raise ArgumentError, "legacy client identity requires a valid session and client id"
      end

      namespace = [LEGACY_UUID_NAMESPACE.delete("-")].pack("H*")
      bytes = Digest::SHA1.digest(namespace + "#{session_id}\0#{legacy_client_id}").bytes.first(16)
      bytes[6] = (bytes[6] & 0x0f) | 0x50
      bytes[8] = (bytes[8] & 0x3f) | 0x80
      hex = bytes.pack("C*").unpack1("H*")
      "#{hex[0, 8]}-#{hex[8, 4]}-#{hex[12, 4]}-#{hex[16, 4]}-#{hex[20, 12]}"
    end

    scope :pending, -> { where(status: "pending") }
    scope :acknowledged, -> { where(status: "acknowledged") }
    scope :resolved, -> { where(status: "resolved") }
    scope :dismissed, -> { where(status: "dismissed") }
    scope :active, -> { where(status: %w[pending acknowledged]) }
    scope :for_page, ->(url) { where(page_url: url) }
    scope :recent, -> { order(created_at: :desc, id: :desc) }

    # Keyset (cursor) companion to :recent — rows strictly older than the
    # (created_at, id) cursor. Avoids the offset-overlap that repeats a boundary
    # row when annotations are inserted between "Load more" requests.
    scope :before_cursor, ->(created_at, id) {
      where("created_at < :t OR (created_at = :t AND id < :id)", t: created_at, id: id)
    }

    scope :search, ->(query) {
      where("content LIKE :q OR selected_text LIKE :q", q: "%#{sanitize_sql_like(query)}%")
    }

    scope :by_author, ->(name) {
      if connection.adapter_name.downcase.include?("postgres")
        where("metadata->>'author' = ?", name)
      else
        where("json_extract(metadata, '$.author') = ?", name)
      end
    }

    def self.distinct_authors
      if connection.adapter_name.downcase.include?("postgres")
        where("metadata->>'author' IS NOT NULL").distinct.pluck(Arel.sql("metadata->>'author'")).compact.sort
      else
        all.filter_map(&:author_name).uniq.sort
      end
    end

    def author_name
      metadata&.dig("author")
    end

    def apply_browser_state(attributes, dirty_fields: [])
      assign_attributes(attributes.slice(*BROWSER_ATTRIBUTES))
      self.metadata = (metadata || {}).merge(attributes.fetch("metadata", {}).slice(*BROWSER_METADATA_KEYS))
      self.status = attributes["status"] if dirty_fields.include?("status")
      self
    end

    def acknowledge!
      raise "Cannot acknowledge a #{status} annotation" unless status == "pending"

      update!(status: "acknowledged")
    end

    def resolve!(summary: nil)
      raise "Cannot resolve a #{status} annotation" unless status.in?(%w[pending acknowledged])

      transaction do
        add_thread_entry(role: "agent", message: summary) if summary.present?
        update!(status: "resolved")
      end
    end

    def dismiss!(reason: nil)
      raise "Cannot dismiss a #{status} annotation" unless status.in?(%w[pending acknowledged])

      transaction do
        add_thread_entry(role: "agent", message: reason) if reason.present?
        update!(status: "dismissed")
      end
    end

    def add_reply!(message:, role: "agent")
      add_thread_entry(role: role, message: message)
      save!
    end

    def as_api_json
      {
        id: id.to_s,
        clientId: client_uuid,
        userId: user_id,
        authorName: author_name,
        content: content,
        intent: intent,
        severity: severity,
        status: status,
        selectedText: selected_text,
        pageUrl: page_url,
        target: target,
        metadata: metadata,
        thread: thread,
        createdAt: created_at&.iso8601,
        updatedAt: updated_at&.iso8601
      }
    end

    private

    def ensure_client_uuid
      self.client_uuid = if client_uuid.blank?
        SecureRandom.uuid
      else
        self.class.normalize_client_uuid(client_uuid) || client_uuid
      end
    end

    def add_thread_entry(role:, message:)
      self.thread = thread + [{ "role" => role, "message" => message, "timestamp" => Time.current.iso8601 }]
    end

    def thread_must_be_array
      errors.add(:thread, "must be an array") unless thread.is_a?(Array)
    end
  end
end

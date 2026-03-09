# frozen_string_literal: true

module RailsMarkup
  class Annotation < ActiveRecord::Base
    self.table_name = RailsMarkup.config.table_name

    INTENTS = %w[fix change question approve].freeze
    SEVERITIES = %w[suggestion important blocking].freeze
    STATUSES = %w[pending acknowledged resolved dismissed].freeze

    # Serialize JSON columns for non-JSONB adapters (SQLite, MySQL)
    serialize :target, coder: JSON
    serialize :metadata, coder: JSON
    serialize :thread, coder: JSON

    validates :content, presence: true
    validates :page_url, presence: true
    validates :intent, inclusion: { in: INTENTS }
    validates :severity, inclusion: { in: SEVERITIES }
    validates :status, inclusion: { in: STATUSES }

    scope :pending, -> { where(status: "pending") }
    scope :acknowledged, -> { where(status: "acknowledged") }
    scope :resolved, -> { where(status: "resolved") }
    scope :dismissed, -> { where(status: "dismissed") }
    scope :active, -> { where(status: %w[pending acknowledged]) }
    scope :for_page, ->(url) { where(page_url: url) }
    scope :recent, -> { order(created_at: :desc) }

    def acknowledge!
      update!(status: "acknowledged")
    end

    def resolve!(summary: nil)
      transaction do
        add_thread_entry(role: "agent", message: summary) if summary.present?
        update!(status: "resolved")
      end
    end

    def dismiss!(reason: nil)
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

    def add_thread_entry(role:, message:)
      self.thread = thread + [{ "role" => role, "message" => message, "timestamp" => Time.current.iso8601 }]
    end
  end
end

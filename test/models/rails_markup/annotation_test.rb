# frozen_string_literal: true

require_relative "../../engine_test_helper"

module RailsMarkup
  class AnnotationTest < ActiveSupport::TestCase
    # --- Validations ---

    test "valid with all required attributes" do
      annotation = create_annotation!
      assert annotation.persisted?
    end

    test "requires content" do
      annotation = Annotation.new(page_url: "/test", content: nil)
      assert_not annotation.valid?
      assert_includes annotation.errors[:content], "can't be blank"
    end

    test "requires page_url" do
      annotation = Annotation.new(content: "Fix this", page_url: nil)
      assert_not annotation.valid?
      assert_includes annotation.errors[:page_url], "can't be blank"
    end

    test "validates intent inclusion" do
      annotation = Annotation.new(content: "Fix", page_url: "/test", intent: "invalid")
      assert_not annotation.valid?
      assert_includes annotation.errors[:intent], "is not included in the list"
    end

    test "validates severity inclusion" do
      annotation = Annotation.new(content: "Fix", page_url: "/test", severity: "invalid")
      assert_not annotation.valid?
      assert_includes annotation.errors[:severity], "is not included in the list"
    end

    test "validates status inclusion" do
      annotation = Annotation.new(content: "Fix", page_url: "/test", status: "invalid")
      assert_not annotation.valid?
      assert_includes annotation.errors[:status], "is not included in the list"
    end

    test "accepts all valid intents" do
      Annotation::INTENTS.each do |intent|
        annotation = create_annotation!(intent: intent)
        assert annotation.persisted?, "Expected intent '#{intent}' to be valid"
      end
    end

    test "accepts all valid severities" do
      Annotation::SEVERITIES.each do |severity|
        annotation = create_annotation!(severity: severity)
        assert annotation.persisted?, "Expected severity '#{severity}' to be valid"
      end
    end

    test "accepts all valid statuses" do
      Annotation::STATUSES.each do |status|
        annotation = create_annotation!(status: status)
        assert annotation.persisted?, "Expected status '#{status}' to be valid"
      end
    end

    # --- Defaults ---

    test "defaults intent to change" do
      annotation = Annotation.new
      assert_equal "change", annotation.intent
    end

    test "defaults severity to suggestion" do
      annotation = Annotation.new
      assert_equal "suggestion", annotation.severity
    end

    test "defaults status to pending" do
      annotation = Annotation.new
      assert_equal "pending", annotation.status
    end

    # --- Scopes ---

    test "pending scope returns only pending" do
      pending = create_annotation!(status: "pending")
      create_annotation!(status: "resolved")

      assert_includes Annotation.pending, pending
      assert_equal 1, Annotation.pending.count
    end

    test "acknowledged scope" do
      ack = create_annotation!(status: "acknowledged")
      create_annotation!(status: "pending")

      assert_includes Annotation.acknowledged, ack
      assert_equal 1, Annotation.acknowledged.count
    end

    test "resolved scope" do
      resolved = create_annotation!(status: "resolved")
      create_annotation!(status: "pending")

      assert_includes Annotation.resolved, resolved
      assert_equal 1, Annotation.resolved.count
    end

    test "dismissed scope" do
      dismissed = create_annotation!(status: "dismissed")
      create_annotation!(status: "pending")

      assert_includes Annotation.dismissed, dismissed
      assert_equal 1, Annotation.dismissed.count
    end

    test "active scope returns pending and acknowledged" do
      pending = create_annotation!(status: "pending")
      ack = create_annotation!(status: "acknowledged")
      create_annotation!(status: "resolved")
      create_annotation!(status: "dismissed")

      active = Annotation.active
      assert_includes active, pending
      assert_includes active, ack
      assert_equal 2, active.count
    end

    test "for_page scope filters by page_url" do
      on_page = create_annotation!(page_url: "/specific/page")
      create_annotation!(page_url: "/other/page")

      results = Annotation.for_page("/specific/page")
      assert_includes results, on_page
      assert_equal 1, results.count
    end

    test "recent scope orders by created_at desc" do
      old = create_annotation!
      old.update_column(:created_at, 1.day.ago)
      new_ann = create_annotation!

      assert_equal new_ann, Annotation.recent.first
    end

    # --- Status transitions ---

    test "acknowledge! sets status to acknowledged" do
      annotation = create_annotation!(status: "pending")
      annotation.acknowledge!

      assert_equal "acknowledged", annotation.reload.status
    end

    test "resolve! sets status to resolved" do
      annotation = create_annotation!(status: "pending")
      annotation.resolve!

      assert_equal "resolved", annotation.reload.status
    end

    test "resolve! with summary adds thread entry" do
      annotation = create_annotation!(status: "pending")
      annotation.resolve!(summary: "Fixed the padding")

      assert_equal "resolved", annotation.reload.status
      assert_equal 1, annotation.thread.size
      assert_equal "agent", annotation.thread.last["role"]
      assert_equal "Fixed the padding", annotation.thread.last["message"]
    end

    test "resolve! without summary does not add thread entry" do
      annotation = create_annotation!(status: "pending")
      annotation.resolve!

      assert_equal "resolved", annotation.reload.status
      assert_empty annotation.thread
    end

    test "dismiss! sets status to dismissed" do
      annotation = create_annotation!(status: "pending")
      annotation.dismiss!

      assert_equal "dismissed", annotation.reload.status
    end

    test "dismiss! with reason adds thread entry" do
      annotation = create_annotation!(status: "pending")
      annotation.dismiss!(reason: "Not actionable")

      assert_equal "dismissed", annotation.reload.status
      assert_equal 1, annotation.thread.size
      assert_equal "Not actionable", annotation.thread.last["message"]
    end

    # --- Thread management ---

    test "add_reply! appends to thread" do
      annotation = create_annotation!
      annotation.add_reply!(message: "Working on it", role: "agent")

      assert_equal 1, annotation.reload.thread.size
      entry = annotation.thread.last
      assert_equal "agent", entry["role"]
      assert_equal "Working on it", entry["message"]
      assert entry["timestamp"].present?
    end

    test "add_reply! preserves existing thread entries" do
      annotation = create_annotation!
      annotation.add_reply!(message: "First reply", role: "agent")
      annotation.add_reply!(message: "Second reply", role: "user")

      assert_equal 2, annotation.reload.thread.size
      assert_equal "First reply", annotation.thread.first["message"]
      assert_equal "Second reply", annotation.thread.last["message"]
    end

    test "add_reply! defaults role to agent" do
      annotation = create_annotation!
      annotation.add_reply!(message: "Hello")

      assert_equal "agent", annotation.reload.thread.last["role"]
    end

    # --- Serialization ---

    test "as_api_json returns camelCase hash" do
      annotation = create_annotation!(
        selected_text: "some text",
        page_url: "/test/page"
      )
      json = annotation.as_api_json

      assert_equal annotation.id.to_s, json[:id]
      assert_equal "Fix this element", json[:content]
      assert_equal "change", json[:intent]
      assert_equal "suggestion", json[:severity]
      assert_equal "pending", json[:status]
      assert_equal "some text", json[:selectedText]
      assert_equal "/test/page", json[:pageUrl]
      assert json[:createdAt].present?
    end
  end
end

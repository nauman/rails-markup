# frozen_string_literal: true

require_relative "../../engine_test_helper"

module RailsMarkup
  class AnnotationTest < ActiveSupport::TestCase
    # --- Validations ---

    test "valid with all required attributes" do
      assert annotations(:pending_fix).valid?
    end

    test "invalid without content" do
      annotation = Annotation.new(page_url: "/test")
      assert_not annotation.valid?
      assert_includes annotation.errors[:content], "can't be blank"
    end

    test "invalid without page_url" do
      annotation = Annotation.new(content: "Fix this")
      assert_not annotation.valid?
      assert_includes annotation.errors[:page_url], "can't be blank"
    end

    test "invalid with unknown intent" do
      annotation = Annotation.new(content: "Fix", page_url: "/test", intent: "invalid")
      assert_not annotation.valid?
      assert_includes annotation.errors[:intent], "is not included in the list"
    end

    test "invalid with unknown severity" do
      annotation = Annotation.new(content: "Fix", page_url: "/test", severity: "invalid")
      assert_not annotation.valid?
      assert_includes annotation.errors[:severity], "is not included in the list"
    end

    test "invalid with unknown status" do
      annotation = Annotation.new(content: "Fix", page_url: "/test", status: "invalid")
      assert_not annotation.valid?
      assert_includes annotation.errors[:status], "is not included in the list"
    end

    test "valid without user_id" do
      annotation = Annotation.new(content: "Test", page_url: "/test")
      assert annotation.valid?
      assert_nil annotation.user_id
    end

    test "valid with user_id" do
      annotation = Annotation.new(content: "Test", page_url: "/test", user_id: 42)
      assert annotation.valid?
      assert_equal 42, annotation.user_id
    end

    test "accepts all valid intents" do
      Annotation::INTENTS.each do |intent|
        annotation = Annotation.new(content: "Test", page_url: "/test", intent: intent)
        assert annotation.valid?, "Expected intent '#{intent}' to be valid"
      end
    end

    test "accepts all valid severities" do
      Annotation::SEVERITIES.each do |severity|
        annotation = Annotation.new(content: "Test", page_url: "/test", severity: severity)
        assert annotation.valid?, "Expected severity '#{severity}' to be valid"
      end
    end

    test "accepts all valid statuses" do
      Annotation::STATUSES.each do |status|
        annotation = Annotation.new(content: "Test", page_url: "/test", status: status)
        assert annotation.valid?, "Expected status '#{status}' to be valid"
      end
    end

    # --- Defaults ---

    test "defaults intent to change" do
      assert_equal "change", Annotation.new.intent
    end

    test "defaults severity to suggestion" do
      assert_equal "suggestion", Annotation.new.severity
    end

    test "defaults status to pending" do
      assert_equal "pending", Annotation.new.status
    end

    test "defaults thread to empty array" do
      assert_equal [], Annotation.new.thread
    end

    test "defaults target to empty hash" do
      assert_equal({}, Annotation.new.target)
    end

    test "defaults metadata to empty hash" do
      assert_equal({}, Annotation.new.metadata)
    end

    test "database rejects duplicate client UUIDs" do
      client_uuid = "aaef53ed-01cb-4c69-b49c-d4890f60bcc6"
      Annotation.create!(content: "First", page_url: "/test", client_uuid: client_uuid)

      assert_raises ActiveRecord::RecordNotUnique do
        Annotation.create!(content: "Second", page_url: "/test", client_uuid: client_uuid)
      end
    end

    test "new annotations receive a canonical client UUID" do
      annotation = Annotation.create!(content: "Generated identity", page_url: "/test")

      assert Annotation.valid_client_uuid?(annotation.client_uuid)
    end

    test "noncanonical client UUIDs are rejected" do
      annotation = Annotation.new(content: "Invalid identity", page_url: "/test", client_uuid: "client-123")

      assert_not annotation.valid?
      assert_includes annotation.errors[:client_uuid], "is invalid"
    end

    test "uppercase canonical UUID input is stored lowercase" do
      uppercase = "AD0A7A44-C458-4B05-B6DC-83E791C2A3FE"

      annotation = Annotation.create!(content: "Normalized identity", page_url: "/test", client_uuid: uppercase)

      assert_equal uppercase.downcase, annotation.client_uuid
      assert Annotation.valid_client_uuid?(annotation.client_uuid)
    end

    # --- Scopes ---

    test "pending scope returns only pending annotations" do
      results = Annotation.pending

      assert_includes results, annotations(:pending_fix)
      assert_includes results, annotations(:other_page_pending)
      assert_not_includes results, annotations(:resolved_fix)
      assert_not_includes results, annotations(:dismissed_question)
    end

    test "acknowledged scope returns only acknowledged annotations" do
      results = Annotation.acknowledged

      assert_includes results, annotations(:acknowledged_change)
      assert_not_includes results, annotations(:pending_fix)
    end

    test "resolved scope returns only resolved annotations" do
      results = Annotation.resolved

      assert_includes results, annotations(:resolved_fix)
      assert_not_includes results, annotations(:pending_fix)
    end

    test "dismissed scope returns only dismissed annotations" do
      results = Annotation.dismissed

      assert_includes results, annotations(:dismissed_question)
      assert_not_includes results, annotations(:pending_fix)
    end

    test "active scope returns pending and acknowledged" do
      results = Annotation.active

      assert_includes results, annotations(:pending_fix)
      assert_includes results, annotations(:acknowledged_change)
      assert_includes results, annotations(:other_page_pending)
      assert_not_includes results, annotations(:resolved_fix)
      assert_not_includes results, annotations(:dismissed_question)
    end

    test "for_page scope filters by exact page_url" do
      results = Annotation.for_page("/sites/inventlist")

      assert_includes results, annotations(:pending_fix)
      assert_includes results, annotations(:acknowledged_change)
      assert_not_includes results, annotations(:other_page_pending)
    end

    test "recent scope orders newest first" do
      results = Annotation.recent

      results.each_cons(2) do |newer, older|
        assert newer.created_at >= older.created_at,
          "Expected #{newer.created_at} >= #{older.created_at}"
      end
    end

    test "recent scope uses descending id as a tiebreaker" do
      timestamp = Time.current.change(usec: 0)
      first = Annotation.create!(content: "First", page_url: "/tied", created_at: timestamp, updated_at: timestamp)
      second = Annotation.create!(content: "Second", page_url: "/tied", created_at: timestamp, updated_at: timestamp)

      assert_equal [second.id, first.id], Annotation.where(id: [first.id, second.id]).recent.pluck(:id)
    end

    test "scopes compose — active on specific page" do
      results = Annotation.active.for_page("/sites/inventlist")

      assert_includes results, annotations(:pending_fix)
      assert_includes results, annotations(:acknowledged_change)
      assert_not_includes results, annotations(:other_page_pending)
      assert_not_includes results, annotations(:resolved_fix)
    end

    # --- Search scope ---

    test "search scope finds by content" do
      results = Annotation.search("padding")
      assert_includes results, annotations(:pending_fix)
      assert_not_includes results, annotations(:dismissed_question)
    end

    test "search scope finds by selected_text" do
      results = Annotation.search("Get Started")
      assert_includes results, annotations(:pending_fix)
    end

    test "search scope returns empty for no match" do
      results = Annotation.search("zzz_no_match_zzz")
      assert_empty results
    end

    # --- Author ---

    test "author_name reads from metadata" do
      annotation = Annotation.new(metadata: { "author" => "Alice" })
      assert_equal "Alice", annotation.author_name
    end

    test "author_name returns nil when not set" do
      annotation = Annotation.new(metadata: {})
      assert_nil annotation.author_name
    end

    test "by_author scope filters by author in metadata" do
      ann = Annotation.create!(content: "Test", page_url: "/test", metadata: { "author" => "TestUser" })
      results = Annotation.by_author("TestUser")
      assert_includes results, ann
      assert_not_includes results, annotations(:pending_fix)
    ensure
      ann&.destroy
    end

    test "distinct_authors returns sorted unique authors" do
      ann1 = Annotation.create!(content: "A", page_url: "/t", metadata: { "author" => "Zara" })
      ann2 = Annotation.create!(content: "B", page_url: "/t", metadata: { "author" => "Alice" })
      ann3 = Annotation.create!(content: "C", page_url: "/t", metadata: { "author" => "Zara" }) # duplicate

      authors = Annotation.distinct_authors
      assert_includes authors, "Alice"
      assert_includes authors, "Zara"
      assert_equal authors, authors.sort
    ensure
      [ann1, ann2, ann3].compact.each(&:destroy)
    end

    # --- Status transitions ---

    test "acknowledge! transitions to acknowledged" do
      annotation = annotations(:pending_fix)
      annotation.acknowledge!

      assert_equal "acknowledged", annotation.reload.status
    end

    test "resolve! transitions to resolved" do
      annotation = annotations(:pending_fix)
      annotation.resolve!

      assert_equal "resolved", annotation.reload.status
    end

    test "resolve! with summary adds thread entry" do
      annotation = annotations(:acknowledged_change)
      annotation.resolve!(summary: "Bumped to 48px")

      annotation.reload
      assert_equal "resolved", annotation.status
      assert_equal 1, annotation.thread.size

      entry = annotation.thread.last
      assert_equal "agent", entry["role"]
      assert_equal "Bumped to 48px", entry["message"]
      assert entry["timestamp"].present?
    end

    test "resolve! without summary skips thread entry" do
      annotation = annotations(:pending_fix)
      annotation.resolve!

      assert_equal "resolved", annotation.reload.status
      assert_empty annotation.thread
    end

    test "dismiss! transitions to dismissed" do
      annotation = annotations(:pending_fix)
      annotation.dismiss!

      assert_equal "dismissed", annotation.reload.status
    end

    test "dismiss! with reason adds thread entry" do
      annotation = annotations(:pending_fix)
      annotation.dismiss!(reason: "Working as designed")

      annotation.reload
      assert_equal "dismissed", annotation.status
      assert_equal 1, annotation.thread.size
      assert_equal "Working as designed", annotation.thread.last["message"]
    end

    test "dismiss! without reason skips thread entry" do
      annotation = annotations(:pending_fix)
      annotation.dismiss!

      assert_empty annotation.reload.thread
    end

    # --- Thread management ---

    test "add_reply! appends entry to thread" do
      annotation = annotations(:pending_fix)
      annotation.add_reply!(message: "Looking into it", role: "agent")

      annotation.reload
      assert_equal 1, annotation.thread.size

      entry = annotation.thread.last
      assert_equal "agent", entry["role"]
      assert_equal "Looking into it", entry["message"]
      assert entry["timestamp"].present?
    end

    test "add_reply! preserves existing entries" do
      annotation = annotations(:resolved_fix)
      existing_count = annotation.thread.size

      annotation.add_reply!(message: "Follow-up note", role: "user")

      assert_equal existing_count + 1, annotation.reload.thread.size
      assert_equal "Follow-up note", annotation.thread.last["message"]
    end

    test "add_reply! defaults role to agent" do
      annotation = annotations(:pending_fix)
      annotation.add_reply!(message: "On it")

      assert_equal "agent", annotation.reload.thread.last["role"]
    end

    test "multiple replies build conversation" do
      annotation = annotations(:pending_fix)
      annotation.add_reply!(message: "Looking into it", role: "agent")
      annotation.add_reply!(message: "Any update?", role: "user")
      annotation.add_reply!(message: "Fixed in latest deploy", role: "agent")

      assert_equal 3, annotation.reload.thread.size
      assert_equal %w[agent user agent], annotation.thread.map { |e| e["role"] }
    end

    # --- Serialization ---

    test "as_api_json returns camelCase keys" do
      json = annotations(:pending_fix).as_api_json

      assert_equal annotations(:pending_fix).id.to_s, json[:id]
      assert_equal "Button padding is off on mobile — needs 12px instead of 8px", json[:content]
      assert_equal "fix", json[:intent]
      assert_equal "important", json[:severity]
      assert_equal "pending", json[:status]
      assert_equal "Get Started", json[:selectedText]
      assert_equal "/sites/inventlist", json[:pageUrl]
      assert json[:createdAt].present?
      assert json[:updatedAt].present?
    end

    test "as_api_json includes target and metadata" do
      json = annotations(:pending_fix).as_api_json

      assert json[:target].is_a?(Hash)
      assert json[:metadata].is_a?(Hash)
      assert json[:thread].is_a?(Array)
    end

    test "as_api_json includes authorName" do
      annotation = Annotation.new(content: "Test", page_url: "/test", metadata: { "author" => "Alice" })
      json = annotation.as_api_json
      assert_equal "Alice", json[:authorName]
    end

    test "as_api_json includes clientId" do
      client_uuid = "e43bc83a-7207-499d-8500-9ae1f451ac5e"
      annotation = Annotation.new(content: "Test", page_url: "/test", client_uuid: client_uuid)

      assert_equal client_uuid, annotation.as_api_json[:clientId]
    end

    test "as_api_json authorName is nil when no author" do
      json = annotations(:pending_fix).as_api_json
      assert_nil json[:authorName]
    end

    test "as_api_json includes thread entries for resolved annotation" do
      json = annotations(:resolved_fix).as_api_json

      assert json[:thread].size >= 1
      assert_equal "agent", json[:thread].first["role"]
    end
  end
end

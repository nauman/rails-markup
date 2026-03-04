# frozen_string_literal: true

require_relative "test_helper"

class StoreTest < Minitest::Test
  def setup
    @store = RailsMarkup::Store.new
  end

  # --- Sessions ---

  def test_create_session
    session = @store.create_session(url: "http://localhost:3000/sites/test")
    assert session.id
    assert_equal "http://localhost:3000/sites/test", session.url
    assert_equal [], session.annotations
  end

  def test_create_session_with_metadata
    session = @store.create_session(url: "http://example.com", metadata: { framework: "rails" })
    assert_equal({ framework: "rails" }, session.metadata)
  end

  def test_get_session
    session = @store.create_session(url: "http://example.com")
    found = @store.get_session(session.id)
    assert_equal session.id, found.id
  end

  def test_get_session_not_found
    assert_nil @store.get_session("nonexistent")
  end

  def test_list_sessions
    @store.create_session(url: "http://one.com")
    @store.create_session(url: "http://two.com")
    assert_equal 2, @store.list_sessions.size
  end

  # --- Annotations ---

  def test_create_annotation
    session = @store.create_session(url: "http://example.com")
    ann = @store.create_annotation(
      session_id: session.id,
      target: "div.hero",
      content: "Make this bigger"
    )
    assert ann.id
    assert_equal "pending", ann.status
    assert_equal "change", ann.intent
    assert_equal "suggestion", ann.severity
    assert_equal 1, session.annotations.size
  end

  def test_create_annotation_invalid_session
    assert_nil @store.create_annotation(session_id: "nope", target: "div", content: "test")
  end

  def test_create_annotation_with_selected_text
    session = @store.create_session(url: "http://example.com")
    ann = @store.create_annotation(
      session_id: session.id,
      target: "p.intro",
      content: "Fix typo",
      selected_text: "teh quick brown fox"
    )
    assert_equal "teh quick brown fox", ann.selected_text
  end

  def test_get_annotation
    session = @store.create_session(url: "http://example.com")
    ann = @store.create_annotation(session_id: session.id, target: "div", content: "test")
    found = @store.get_annotation(ann.id)
    assert_equal ann.id, found.id
  end

  def test_pending_for_session
    session = @store.create_session(url: "http://example.com")
    @store.create_annotation(session_id: session.id, target: "div", content: "one")
    @store.create_annotation(session_id: session.id, target: "p", content: "two")
    assert_equal 2, @store.pending_for_session(session.id).size
  end

  def test_all_pending_across_sessions
    s1 = @store.create_session(url: "http://one.com")
    s2 = @store.create_session(url: "http://two.com")
    @store.create_annotation(session_id: s1.id, target: "div", content: "a")
    @store.create_annotation(session_id: s2.id, target: "p", content: "b")
    assert_equal 2, @store.all_pending.size
  end

  # --- Status transitions ---

  def test_acknowledge
    session = @store.create_session(url: "http://example.com")
    ann = @store.create_annotation(session_id: session.id, target: "div", content: "test")
    result = @store.acknowledge(ann.id)
    assert_equal "acknowledged", result.status
  end

  def test_resolve_with_summary
    session = @store.create_session(url: "http://example.com")
    ann = @store.create_annotation(session_id: session.id, target: "div", content: "test")
    result = @store.resolve(ann.id, summary: "Fixed the padding")
    assert_equal "resolved", result.status
    assert_equal 1, result.thread.size
    assert_equal "Fixed the padding", result.thread.first[:message]
  end

  def test_dismiss_with_reason
    session = @store.create_session(url: "http://example.com")
    ann = @store.create_annotation(session_id: session.id, target: "div", content: "test")
    result = @store.dismiss(ann.id, reason: "Working as intended")
    assert_equal "dismissed", result.status
    assert_equal "Working as intended", result.thread.first[:message]
  end

  def test_reply
    session = @store.create_session(url: "http://example.com")
    ann = @store.create_annotation(session_id: session.id, target: "div", content: "test")
    result = @store.reply(ann.id, message: "Can you clarify?")
    assert_equal 1, result.thread.size
    assert_equal "agent", result.thread.first[:role]
    assert_equal "Can you clarify?", result.thread.first[:message]
  end

  def test_resolve_nonexistent_annotation
    assert_nil @store.resolve("nope", summary: "test")
  end

  def test_resolved_annotations_not_in_pending
    session = @store.create_session(url: "http://example.com")
    ann = @store.create_annotation(session_id: session.id, target: "div", content: "test")
    @store.resolve(ann.id, summary: "Done")
    assert_equal 0, @store.pending_for_session(session.id).size
  end

  # --- Serialization ---

  def test_serialize_session
    session = @store.create_session(url: "http://example.com", metadata: { tool: "rails-markup" })
    @store.create_annotation(session_id: session.id, target: "div", content: "note")
    data = @store.serialize_session(session)
    assert_equal session.id, data[:id]
    assert_equal "http://example.com", data[:url]
    assert_equal 1, data[:annotations].size
  end

  def test_serialize_annotation
    session = @store.create_session(url: "http://example.com")
    ann = @store.create_annotation(session_id: session.id, target: "div.hero", content: "Fix this",
                                   intent: "fix", severity: "blocking")
    data = @store.serialize_annotation(ann)
    assert_equal ann.id, data[:id]
    assert_equal "div.hero", data[:target]
    assert_equal "fix", data[:intent]
    assert_equal "blocking", data[:severity]
    assert_equal "pending", data[:status]
  end

  # --- Subscriptions ---

  def test_subscribe_receives_annotation_events
    session = @store.create_session(url: "http://example.com")
    events = []
    @store.subscribe(session.id) { |data| events << data }
    @store.create_annotation(session_id: session.id, target: "div", content: "test")
    assert_equal 1, events.size
    assert_equal "annotation_created", events.first[:type]
  end

  def test_subscribe_receives_resolve_events
    session = @store.create_session(url: "http://example.com")
    ann = @store.create_annotation(session_id: session.id, target: "div", content: "test")
    events = []
    @store.subscribe(session.id) { |data| events << data }
    @store.resolve(ann.id, summary: "Done")
    assert_equal 1, events.size
    assert_equal "resolved", events.first[:status]
  end

  def test_unsubscribe
    session = @store.create_session(url: "http://example.com")
    events = []
    sub = @store.subscribe(session.id) { |data| events << data }
    @store.unsubscribe(sub)
    @store.create_annotation(session_id: session.id, target: "div", content: "test")
    assert_equal 0, events.size
  end
end

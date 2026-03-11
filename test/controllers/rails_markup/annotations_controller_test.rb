# frozen_string_literal: true

require_relative "../../engine_test_helper"

module RailsMarkup
  class AnnotationsControllerTest < ActionDispatch::IntegrationTest
    # --- Session ---

    test "create_session returns prefixed id" do
      post sessions_path, params: { url: "/sites/inventlist" }, as: :json

      assert_response :success
      body = response.parsed_body
      assert body["id"].start_with?("rm-")
      assert_equal "/sites/inventlist", body["url"]
    end

    # --- Create ---

    test "create with valid params persists annotation" do
      assert_difference "Annotation.count", 1 do
        post session_annotations_path("test-session"),
          params: { page_url: "/sites/inventlist", content: "Fix spacing", intent: "fix", severity: "important" },
          as: :json
      end

      assert_response :created
      body = response.parsed_body
      assert_equal "Fix spacing", body["content"]
      assert_equal "fix", body["intent"]
      assert_equal "important", body["severity"]
      assert_equal "/sites/inventlist", body["pageUrl"]
    end

    test "create sets page_url from param" do
      post session_annotations_path("test-session"),
        params: { page_url: "/explicit/path", content: "Test" },
        as: :json

      assert_response :created
      assert_equal "/explicit/path", Annotation.last.page_url
    end

    test "create falls back to referer when page_url missing" do
      post session_annotations_path("test-session"),
        params: { content: "Test" },
        headers: { "Referer" => "http://test.host/from-referer" },
        as: :json

      assert_response :created
      assert_equal "http://test.host/from-referer", Annotation.last.page_url
    end

    test "create with empty content returns errors" do
      assert_no_difference "Annotation.count" do
        post session_annotations_path("test-session"),
          params: { content: "" },
          as: :json
      end

      assert_response :unprocessable_entity
      body = response.parsed_body
      assert body["errors"].any? { |e| e.include?("Content") }
    end

    test "create deduplicates by localId and page_url" do
      # First submission — creates
      assert_difference "Annotation.count", 1 do
        post session_annotations_path("test-session"),
          params: { page_url: "/dedup-test", content: "Fix spacing", intent: "fix", severity: "important",
                    metadata: { localId: 42 } },
          as: :json
      end
      assert_response :created
      first_id = response.parsed_body["id"]

      # Duplicate submission — returns existing, no new record
      assert_no_difference "Annotation.count" do
        post session_annotations_path("test-session"),
          params: { page_url: "/dedup-test", content: "Fix spacing", intent: "fix", severity: "important",
                    metadata: { localId: 42 } },
          as: :json
      end
      assert_response :ok
      assert_equal first_id, response.parsed_body["id"]
    end

    test "create allows same localId on different pages" do
      post session_annotations_path("test-session"),
        params: { page_url: "/page-a", content: "Fix A", metadata: { localId: 1 } },
        as: :json
      assert_response :created

      assert_difference "Annotation.count", 1 do
        post session_annotations_path("test-session"),
          params: { page_url: "/page-b", content: "Fix B", metadata: { localId: 1 } },
          as: :json
      end
      assert_response :created
    end

    test "create normalizes camelCase selectedText to selected_text" do
      post session_annotations_path("test-session"),
        params: { page_url: "/test", content: "Fix", selectedText: "highlighted text" },
        as: :json

      assert_response :created
      assert_equal "highlighted text", Annotation.last.selected_text
    end

    test "create stores target as hash" do
      post session_annotations_path("test-session"),
        params: { page_url: "/test", content: "Fix", target: { selector: "div.hero", cssPath: "main > div" } },
        as: :json

      assert_response :created
      assert_equal "div.hero", Annotation.last.target["selector"]
    end

    # --- Health ---

    test "health returns ok" do
      get health_path, as: :json

      assert_response :success
      assert response.parsed_body["ok"]
    end

    # --- Status actions ---

    test "acknowledge transitions to acknowledged" do
      annotation = annotations(:pending_fix)

      post acknowledge_annotation_path(annotation), as: :json

      assert_response :success
      assert_equal "acknowledged", annotation.reload.status
      assert_equal "acknowledged", response.parsed_body["status"]
    end

    test "resolve with summary transitions and adds thread" do
      annotation = annotations(:pending_fix)

      post resolve_annotation_path(annotation),
        params: { summary: "Fixed padding to 12px" }, as: :json

      assert_response :success
      annotation.reload
      assert_equal "resolved", annotation.status
      assert_equal "Fixed padding to 12px", annotation.thread.last["message"]
    end

    test "dismiss with reason transitions and adds thread" do
      annotation = annotations(:pending_fix)

      post dismiss_annotation_path(annotation),
        params: { reason: "Working as designed" }, as: :json

      assert_response :success
      assert_equal "dismissed", annotation.reload.status
    end

    test "reply adds thread entry without changing status" do
      annotation = annotations(:pending_fix)

      post reply_annotation_path(annotation),
        params: { message: "Looking into it" }, as: :json

      assert_response :success
      annotation.reload
      assert_equal "pending", annotation.status
      assert_equal 1, annotation.thread.size
      assert_equal "Looking into it", annotation.thread.last["message"]
    end

    private

    # Named route helpers for the engine's API endpoints
    def sessions_path
      rails_markup.url_for(controller: "rails_markup/annotations", action: "create_session", only_path: true)
    end

    def session_annotations_path(session_id)
      rails_markup.url_for(controller: "rails_markup/annotations", action: "create", session_id: session_id, only_path: true)
    end

    def health_path
      rails_markup.url_for(controller: "rails_markup/annotations", action: "health", only_path: true)
    end

    def acknowledge_annotation_path(annotation)
      rails_markup.url_for(controller: "rails_markup/annotations", action: "acknowledge", id: annotation.id, only_path: true)
    end

    def resolve_annotation_path(annotation)
      rails_markup.url_for(controller: "rails_markup/annotations", action: "resolve", id: annotation.id, only_path: true)
    end

    def dismiss_annotation_path(annotation)
      rails_markup.url_for(controller: "rails_markup/annotations", action: "dismiss", id: annotation.id, only_path: true)
    end

    def reply_annotation_path(annotation)
      rails_markup.url_for(controller: "rails_markup/annotations", action: "reply", id: annotation.id, only_path: true)
    end
  end
end

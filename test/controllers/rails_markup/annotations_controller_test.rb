# frozen_string_literal: true

require_relative "../../engine_test_helper"

module RailsMarkup
  class AnnotationsControllerTest < ActionDispatch::IntegrationTest
    BROWSER_UUID = "2e843a25-35f4-4a22-8968-1fd60a21a27c"
    DELETE_UUID = "40d8e459-e436-4e2a-a0b7-c5d647a1638c"
    STATUS_UUID = "ea20742d-f640-4984-ab7a-cf957d56c7e2"
    DIRTY_UUID = "157784ee-d8a3-45ac-99e4-6d44cd3a0b20"
    RACE_UUID = "169253af-c17c-4f37-80ff-12de5e808c73"

    setup do
      @csrf_token = authenticate_rails_markup_admin
    end

    test "unauthenticated health is rejected" do
      reset!

      get health_path, as: :json

      assert_redirected_to "/rails_markup_test_session"
    end

    test "unauthenticated mutation is rejected" do
      reset!

      assert_no_difference "Annotation.count" do
        post session_annotations_path("test-session"), params: { content: "Blocked" }, as: :json
      end

      assert_redirected_to "/rails_markup_test_session"
    end

    test "authenticated mutation without csrf is rejected" do
      with_forgery_protection do
        assert_raises ActionController::InvalidAuthenticityToken do
          post session_annotations_path("test-session"), params: { content: "Blocked" }, as: :json
        end
      end
    end

    test "authenticated mutation with valid csrf succeeds" do
      with_forgery_protection do
        post session_annotations_path("test-session"),
          params: { content: "Accepted" },
          headers: { "X-CSRF-Token" => @csrf_token },
          as: :json

        assert_response :created
      end
    end

    test "unauthenticated pull is rejected" do
      reset!

      get "/feedback/api/annotations", params: { page_url: "/private" }, as: :json

      assert_redirected_to "/rails_markup_test_session"
    end

    test "pull returns only the exact page in deterministic recent order" do
      older = Annotation.create!(content: "Older", page_url: "/same?tab=one", created_at: 2.minutes.ago)
      newer = Annotation.create!(content: "Newer", page_url: "/same?tab=one", created_at: 1.minute.ago)
      Annotation.create!(content: "Other", page_url: "/same?tab=two")

      get "/feedback/api/annotations", params: { page_url: "/same?tab=one" }, as: :json

      assert_response :ok
      assert_equal [newer.id.to_s, older.id.to_s], response.parsed_body.map { |annotation| annotation["id"] }
      assert response.parsed_body.all? { |annotation| Annotation.valid_client_uuid?(annotation["clientId"]) }
    end

    test "pull keeps query string variants separate" do
      Annotation.create!(content: "One", page_url: "/same?tab=one")
      Annotation.create!(content: "Two", page_url: "/same?tab=two")

      get "/feedback/api/annotations", params: { page_url: "/same?tab=two" }, as: :json

      assert_equal ["Two"], response.parsed_body.map { |annotation| annotation["content"] }
    end

    test "put creates and returns the uuid annotation" do
      assert_difference "Annotation.count", 1 do
        put "/feedback/api/annotations/#{BROWSER_UUID}",
          params: { content: "Created", page_url: "/put", intent: "fix", severity: "important",
                    selectedText: "selection", target: { selector: "main" }, metadata: { tool: "toolbar" } },
          as: :json
      end

      assert_response :ok
      assert_equal BROWSER_UUID, response.parsed_body["clientId"]
      assert_equal "Created", response.parsed_body["content"]
      assert_equal "selection", response.parsed_body["selectedText"]
    end

    test "put updates the uuid annotation and preserves server owned fields" do
      annotation = Annotation.create!(
        client_uuid: BROWSER_UUID,
        content: "Before",
        page_url: "/before",
        user_id: 42,
        status: "acknowledged",
        metadata: { "author" => "Server Author", "serverOnly" => true, "tool" => "old" },
        thread: [{ "role" => "agent", "message" => "Server reply" }]
      )

      put "/feedback/api/annotations/#{BROWSER_UUID}",
        params: { id: "forged", userId: 99, author: "Forged", content: "After", page_url: "/after",
                  status: "pending", createdAt: "2000-01-01", thread: [],
                  metadata: { tool: "new", serverOnly: false } },
        as: :json

      assert_response :ok
      annotation.reload
      assert_equal "After", annotation.content
      assert_equal "/after", annotation.page_url
      assert_equal "acknowledged", annotation.status
      assert_equal 42, annotation.user_id
      assert_equal [{ "role" => "agent", "message" => "Server reply" }], annotation.thread
      assert_equal({ "author" => "Server Author", "serverOnly" => true, "tool" => "new" }, annotation.metadata)
    end

    test "delete is idempotent and returns no content twice" do
      Annotation.create!(client_uuid: DELETE_UUID, content: "Delete", page_url: "/delete")

      assert_difference "Annotation.count", -1 do
        delete "/feedback/api/annotations/#{DELETE_UUID}", as: :json
      end
      assert_response :no_content

      assert_no_difference "Annotation.count" do
        delete "/feedback/api/annotations/#{DELETE_UUID}", as: :json
      end
      assert_response :no_content
    end

    test "put rejects whitespace and oversized uuids" do
      put "/feedback/api/annotations/%20%20%20", params: { content: "No", page_url: "/" }, as: :json
      assert_response :unprocessable_entity

      put "/feedback/api/annotations/#{"a" * 65}", params: { content: "No", page_url: "/" }, as: :json
      assert_response :unprocessable_entity

      assert_no_difference "Annotation.count" do
        put "/feedback/api/annotations/not-a-uuid", params: { content: "No", page_url: "/" }, as: :json
      end
      assert_response :unprocessable_entity
    end

    test "compatibility post assigns distinct canonical uuids to blank client ids" do
      post session_annotations_path("test-session"),
        params: { content: "First", clientId: "   " }, as: :json
      assert_response :created

      post session_annotations_path("test-session"),
        params: { content: "Second", clientId: "" }, as: :json
      assert_response :created

      client_uuids = Annotation.where(content: %w[First Second]).pluck(:client_uuid)
      assert_equal 2, client_uuids.uniq.length
      assert client_uuids.all? { |client_uuid| RailsMarkup::Annotation.valid_client_uuid?(client_uuid) }
    end

    test "compatibility post rejects client metadata author" do
      assert_no_difference "Annotation.count" do
        post session_annotations_path("test-session"),
          params: { content: "Forged", metadata: { author: "Browser Author" } }, as: :json
      end

      assert_response :unprocessable_entity
    end

    test "put updates status only when status is explicitly dirty" do
      annotation = Annotation.create!(client_uuid: STATUS_UUID, content: "Status", page_url: "/status", status: "acknowledged")

      put "/feedback/api/annotations/#{STATUS_UUID}",
        params: { content: "Ordinary edit", page_url: "/status", status: "resolved" }, as: :json
      assert_response :ok
      assert_equal "acknowledged", annotation.reload.status

      put "/feedback/api/annotations/#{STATUS_UUID}",
        params: { content: "Ordinary edit", page_url: "/status", status: "resolved", dirtyFields: ["status"] },
        as: :json
      assert_response :ok
      assert_equal "resolved", annotation.reload.status
    end

    test "put accepts browser owned dirty fields" do
      annotation = Annotation.create!(client_uuid: DIRTY_UUID, content: "Before", page_url: "/dirty")

      put "/feedback/api/annotations/#{DIRTY_UUID}",
        params: {
          content: "After",
          page_url: "/dirty",
          target: { selector: "main" },
          selectedText: "Selected",
          dirtyFields: %w[content target selectedText]
        },
        as: :json

      assert_response :ok
      annotation.reload
      assert_equal "After", annotation.content
      assert_equal({ "selector" => "main" }, annotation.target)
      assert_equal "Selected", annotation.selected_text
    end

    test "put rejects invalid dirty fields and invalid explicitly dirty status" do
      put "/feedback/api/annotations/ce79717f-4988-4555-a3e2-67a936d90ef0",
        params: { content: "No", page_url: "/", dirtyFields: ["thread"] }, as: :json
      assert_response :unprocessable_entity

      put "/feedback/api/annotations/6fff8120-f71c-4610-805e-3aa23cfd2862",
        params: { content: "No", page_url: "/", dirtyFields: ["author"] }, as: :json
      assert_response :unprocessable_entity

      put "/feedback/api/annotations/079257f9-d184-4dc0-9979-8b66c5b6ce69",
        params: { content: "No", page_url: "/", status: "resolved", dirtyFields: "status" }, as: :json
      assert_response :unprocessable_entity

      put "/feedback/api/annotations/92316009-09c6-4482-8f16-a25046092cf1",
        params: { content: "No", page_url: "/", status: "invented", dirtyFields: ["status"] }, as: :json
      assert_response :unprocessable_entity
    end

    test "put reloads and updates the winner of a unique uuid race" do
      candidate = Annotation.new(client_uuid: RACE_UUID, content: "Desired", page_url: "/race")
      race = proc do
        Annotation.create!(client_uuid: RACE_UUID, content: "Winner", page_url: "/race", metadata: { "author" => "Server" })
        raise ActiveRecord::RecordNotUnique
      end

      Annotation.stub :find_or_initialize_by, candidate do
        candidate.stub :save!, race do
          assert_difference "Annotation.count", 1 do
            put "/feedback/api/annotations/#{RACE_UUID}",
              params: { content: "Desired", page_url: "/race", metadata: { tool: "toolbar" } }, as: :json
          end
        end
      end

      assert_response :ok
      assert_equal 1, Annotation.where(client_uuid: RACE_UUID).count
      winner = Annotation.find_by!(client_uuid: RACE_UUID)
      assert_equal "Desired", winner.content
      assert_equal({ "author" => "Server", "tool" => "toolbar" }, winner.metadata)
    end

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

    test "create deduplicates an exact replay by client id" do
      # First submission — creates
      assert_difference "Annotation.count", 1 do
        post session_annotations_path("test-session"),
          params: { page_url: "/dedup-test", content: "Fix spacing", intent: "fix", severity: "important",
                    clientId: "92bbf4ef-7f45-4c20-a56a-21b7cc21ef27", metadata: { localId: 42 } },
          as: :json
      end
      assert_response :created
      first_id = response.parsed_body["id"]

      # Duplicate submission — returns existing, no new record
      assert_no_difference "Annotation.count" do
        post session_annotations_path("test-session"),
          params: { page_url: "/dedup-test", content: "Fix spacing", intent: "fix", severity: "important",
                    clientId: "92bbf4ef-7f45-4c20-a56a-21b7cc21ef27", metadata: { localId: 42 } },
          as: :json
      end
      assert_response :ok
      assert_equal first_id, response.parsed_body["id"]
    end

    test "create allows reused localId on the same page when client ids differ" do
      post session_annotations_path("test-session"),
        params: { page_url: "/same-page", content: "Fix A", clientId: "2dd40ebd-385c-4386-896c-53b998c298a2",
                  metadata: { localId: 1 } },
        as: :json
      assert_response :created

      assert_difference "Annotation.count", 1 do
        post session_annotations_path("test-session"),
          params: { page_url: "/same-page", content: "Fix B", clientId: "51db87d0-9d98-44ec-84f4-aae7c7935fe7",
                    metadata: { localId: 1 } },
          as: :json
      end
      assert_response :created
    end

    test "create rejects a client id reused for different content" do
      client_id = "8b018697-a8bf-401e-88af-c0185ff92541"
      post session_annotations_path("test-session"),
        params: { page_url: "/dedup-test", content: "Original", clientId: client_id },
        as: :json
      assert_response :created

      assert_no_difference "Annotation.count" do
        post session_annotations_path("test-session"),
          params: { page_url: "/dedup-test", content: "Different", clientId: client_id },
          as: :json
      end

      assert_response :conflict
      assert_equal "client id already used for a different annotation", response.parsed_body["error"]
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

    def with_forgery_protection
      original = ActionController::Base.allow_forgery_protection
      ActionController::Base.allow_forgery_protection = true
      yield
    ensure
      ActionController::Base.allow_forgery_protection = original
    end

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

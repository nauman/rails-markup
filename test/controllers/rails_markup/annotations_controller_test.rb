# frozen_string_literal: true

require_relative "../../engine_test_helper"

module RailsMarkup
  class AnnotationsControllerTest < ActionDispatch::IntegrationTest
    setup do
      @annotation = create_annotation!
    end

    # --- Session ---

    test "create_session returns session id" do
      post rails_markup.url_for(controller: "rails_markup/annotations", action: "create_session"), params: { url: "/test" }, as: :json
      assert_response :success

      body = JSON.parse(response.body)
      assert body["id"].start_with?("rm-")
      assert_equal "/test", body["url"]
    end

    # --- Create annotation ---

    test "create annotation with valid params" do
      assert_difference "Annotation.count", 1 do
        post rails_markup.url_for(controller: "rails_markup/annotations", action: "create", session_id: "test-session"),
          params: { content: "Fix button", intent: "fix", severity: "important", metadata: { url: "/page" } },
          as: :json
      end

      assert_response :created
      body = JSON.parse(response.body)
      assert_equal "Fix button", body["content"]
      assert_equal "fix", body["intent"]
      assert_equal "important", body["severity"]
    end

    test "create annotation with invalid params returns errors" do
      post rails_markup.url_for(controller: "rails_markup/annotations", action: "create", session_id: "test-session"),
        params: { content: "", intent: "fix" },
        as: :json

      assert_response :unprocessable_entity
      body = JSON.parse(response.body)
      assert body["errors"].any?
    end

    # --- Health ---

    test "health returns ok" do
      get rails_markup.url_for(controller: "rails_markup/annotations", action: "health"), as: :json
      assert_response :success

      body = JSON.parse(response.body)
      assert body["ok"]
    end

    # --- Status actions ---

    test "acknowledge annotation" do
      post rails_markup.url_for(controller: "rails_markup/annotations", action: "acknowledge", id: @annotation.id), as: :json
      assert_response :success

      body = JSON.parse(response.body)
      assert_equal "acknowledged", body["status"]
      assert_equal "acknowledged", @annotation.reload.status
    end

    test "resolve annotation with summary" do
      post rails_markup.url_for(controller: "rails_markup/annotations", action: "resolve", id: @annotation.id),
        params: { summary: "Done" }, as: :json
      assert_response :success

      body = JSON.parse(response.body)
      assert_equal "resolved", body["status"]
      assert_equal "resolved", @annotation.reload.status
    end

    test "dismiss annotation with reason" do
      post rails_markup.url_for(controller: "rails_markup/annotations", action: "dismiss", id: @annotation.id),
        params: { reason: "Not needed" }, as: :json
      assert_response :success

      assert_equal "dismissed", @annotation.reload.status
    end

    test "reply to annotation" do
      post rails_markup.url_for(controller: "rails_markup/annotations", action: "reply", id: @annotation.id),
        params: { message: "Looking into it" }, as: :json
      assert_response :success

      assert_equal 1, @annotation.reload.thread.size
    end
  end
end

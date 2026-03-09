# frozen_string_literal: true

require_relative "../../../engine_test_helper"

module RailsMarkup
  module External
    class AnnotationsControllerTest < ActionDispatch::IntegrationTest
      TOKEN = "test-token-123"

      setup do
        @auth = { "Authorization" => "Bearer #{TOKEN}" }
      end

      # --- Token auth ---

      test "returns 401 without token" do
        get external_pending_path
        assert_response :unauthorized
      end

      test "returns 401 with wrong token" do
        get external_pending_path, headers: { "Authorization" => "Bearer wrong" }
        assert_response :unauthorized
      end

      test "returns 404 when api_token not configured" do
        original = RailsMarkup.config.api_token
        RailsMarkup.config.api_token = nil

        get external_pending_path, headers: @auth
        assert_response :not_found
      ensure
        RailsMarkup.config.api_token = original
      end

      # --- Pending ---

      test "pending returns pending annotations" do
        get external_pending_path, headers: @auth

        assert_response :success
        body = response.parsed_body
        ids = body["annotations"].map { |a| a["id"].to_i }

        assert_includes ids, annotations(:pending_fix).id
        assert_includes ids, annotations(:other_page_pending).id
        assert_not_includes ids, annotations(:resolved_fix).id
      end

      # --- Show ---

      test "show returns single annotation" do
        annotation = annotations(:pending_fix)

        get external_show_path(annotation), headers: @auth

        assert_response :success
        body = response.parsed_body
        assert_equal annotation.id.to_s, body["id"]
        assert_equal annotation.content, body["content"]
      end

      # --- Status actions ---

      test "acknowledge transitions status" do
        annotation = annotations(:pending_fix)

        patch external_acknowledge_path(annotation), headers: @auth

        assert_response :success
        assert_equal "acknowledged", annotation.reload.status
      end

      test "resolve with summary transitions and adds thread" do
        annotation = annotations(:pending_fix)

        patch external_resolve_path(annotation),
          params: { summary: "All fixed" }, headers: @auth, as: :json

        assert_response :success
        annotation.reload
        assert_equal "resolved", annotation.status
        assert_equal "All fixed", annotation.thread.last["message"]
      end

      test "dismiss with reason transitions and adds thread" do
        annotation = annotations(:pending_fix)

        patch external_dismiss_path(annotation),
          params: { reason: "Won't fix" }, headers: @auth, as: :json

        assert_response :success
        assert_equal "dismissed", annotation.reload.status
      end

      test "reply adds thread entry" do
        annotation = annotations(:pending_fix)

        patch external_reply_path(annotation),
          params: { message: "Got it" }, headers: @auth, as: :json

        assert_response :success
        annotation.reload
        assert_equal 1, annotation.thread.size
        assert_equal "Got it", annotation.thread.last["message"]
      end

      private

      def external_pending_path
        rails_markup.url_for(controller: "rails_markup/external/annotations", action: "pending", only_path: true)
      end

      def external_show_path(annotation)
        rails_markup.url_for(controller: "rails_markup/external/annotations", action: "show", id: annotation.id, only_path: true)
      end

      def external_acknowledge_path(annotation)
        rails_markup.url_for(controller: "rails_markup/external/annotations", action: "acknowledge", id: annotation.id, only_path: true)
      end

      def external_resolve_path(annotation)
        rails_markup.url_for(controller: "rails_markup/external/annotations", action: "resolve", id: annotation.id, only_path: true)
      end

      def external_dismiss_path(annotation)
        rails_markup.url_for(controller: "rails_markup/external/annotations", action: "dismiss", id: annotation.id, only_path: true)
      end

      def external_reply_path(annotation)
        rails_markup.url_for(controller: "rails_markup/external/annotations", action: "reply", id: annotation.id, only_path: true)
      end
    end
  end
end

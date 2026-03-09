# frozen_string_literal: true

require_relative "../../../engine_test_helper"

module RailsMarkup
  module External
    class AnnotationsControllerTest < ActionDispatch::IntegrationTest
      setup do
        @annotation = create_annotation!
        @token = "test-token-123"
        @auth_headers = { "Authorization" => "Bearer #{@token}" }
      end

      # --- Token auth ---

      test "pending returns 401 without token" do
        get rails_markup.url_for(controller: "rails_markup/external/annotations", action: "pending")
        assert_response :unauthorized
      end

      test "pending returns 401 with wrong token" do
        get rails_markup.url_for(controller: "rails_markup/external/annotations", action: "pending"),
          headers: { "Authorization" => "Bearer wrong-token" }
        assert_response :unauthorized
      end

      test "pending returns 404 when api_token not configured" do
        original = RailsMarkup.config.api_token
        RailsMarkup.config.api_token = nil

        get rails_markup.url_for(controller: "rails_markup/external/annotations", action: "pending"),
          headers: @auth_headers
        assert_response :not_found
      ensure
        RailsMarkup.config.api_token = original
      end

      # --- Endpoints ---

      test "pending returns pending annotations" do
        get rails_markup.url_for(controller: "rails_markup/external/annotations", action: "pending"),
          headers: @auth_headers
        assert_response :success

        body = JSON.parse(response.body)
        assert body["annotations"].is_a?(Array)
        assert body["annotations"].any? { |a| a["id"] == @annotation.id.to_s }
      end

      test "show returns single annotation" do
        get rails_markup.url_for(controller: "rails_markup/external/annotations", action: "show", id: @annotation.id),
          headers: @auth_headers
        assert_response :success

        body = JSON.parse(response.body)
        assert_equal @annotation.id.to_s, body["id"]
      end

      test "acknowledge updates status" do
        patch rails_markup.url_for(controller: "rails_markup/external/annotations", action: "acknowledge", id: @annotation.id),
          headers: @auth_headers
        assert_response :success

        assert_equal "acknowledged", @annotation.reload.status
      end

      test "resolve updates status with summary" do
        patch rails_markup.url_for(controller: "rails_markup/external/annotations", action: "resolve", id: @annotation.id),
          params: { summary: "All fixed" }, headers: @auth_headers, as: :json
        assert_response :success

        assert_equal "resolved", @annotation.reload.status
        assert_equal "All fixed", @annotation.thread.last["message"]
      end

      test "dismiss updates status with reason" do
        patch rails_markup.url_for(controller: "rails_markup/external/annotations", action: "dismiss", id: @annotation.id),
          params: { reason: "Won't fix" }, headers: @auth_headers, as: :json
        assert_response :success

        assert_equal "dismissed", @annotation.reload.status
      end

      test "reply adds thread entry" do
        patch rails_markup.url_for(controller: "rails_markup/external/annotations", action: "reply", id: @annotation.id),
          params: { message: "Got it" }, headers: @auth_headers, as: :json
        assert_response :success

        assert_equal 1, @annotation.reload.thread.size
        assert_equal "Got it", @annotation.thread.last["message"]
      end
    end
  end
end

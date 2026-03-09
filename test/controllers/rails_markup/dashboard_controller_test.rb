# frozen_string_literal: true

require_relative "../../engine_test_helper"

module RailsMarkup
  class DashboardControllerTest < ActionDispatch::IntegrationTest
    setup do
      @annotation = create_annotation!
    end

    # --- Auth gating ---

    test "index renders when auth passes" do
      get rails_markup.root_path
      assert_response :success
    end

    test "index returns 403 when auth fails" do
      original = RailsMarkup.config.auth_check
      RailsMarkup.config.auth_check = ->(_) { false }

      get rails_markup.root_path
      assert_response :forbidden
    ensure
      RailsMarkup.config.auth_check = original
    end

    test "show renders when auth passes" do
      get rails_markup.annotation_path(@annotation)
      assert_response :success
    end

    test "show returns 403 when auth fails" do
      original = RailsMarkup.config.auth_check
      RailsMarkup.config.auth_check = ->(_) { false }

      get rails_markup.annotation_path(@annotation)
      assert_response :forbidden
    ensure
      RailsMarkup.config.auth_check = original
    end

    # --- Index ---

    test "index shows all annotations" do
      get rails_markup.root_path
      assert_response :success
    end

    test "index filters by status" do
      create_annotation!(status: "resolved")
      get rails_markup.root_path(status: "resolved")
      assert_response :success
    end

    test "index filters by page_url" do
      create_annotation!(page_url: "/specific")
      get rails_markup.root_path(page_url: "/specific")
      assert_response :success
    end

    # --- Show ---

    test "show displays annotation" do
      get rails_markup.annotation_path(@annotation)
      assert_response :success
    end

    # --- Update actions ---

    test "update acknowledges annotation" do
      patch rails_markup.annotation_path(@annotation), params: { action_type: "acknowledge" }
      assert_redirected_to rails_markup.annotation_path(@annotation)
      assert_equal "acknowledged", @annotation.reload.status
    end

    test "update resolves annotation with summary" do
      patch rails_markup.annotation_path(@annotation), params: { action_type: "resolve", summary: "Fixed it" }
      assert_redirected_to rails_markup.annotation_path(@annotation)
      assert_equal "resolved", @annotation.reload.status
      assert_equal "Fixed it", @annotation.thread.last["message"]
    end

    test "update dismisses annotation with reason" do
      patch rails_markup.annotation_path(@annotation), params: { action_type: "dismiss", reason: "Not relevant" }
      assert_redirected_to rails_markup.annotation_path(@annotation)
      assert_equal "dismissed", @annotation.reload.status
    end

    test "update adds reply" do
      patch rails_markup.annotation_path(@annotation), params: { action_type: "reply", message: "Working on it", role: "agent" }
      assert_redirected_to rails_markup.annotation_path(@annotation)
      assert_equal 1, @annotation.reload.thread.size
      assert_equal "Working on it", @annotation.thread.last["message"]
    end
  end
end

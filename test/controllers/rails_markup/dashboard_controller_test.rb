# frozen_string_literal: true

require_relative "../../engine_test_helper"

module RailsMarkup
  class DashboardControllerTest < ActionDispatch::IntegrationTest
    # --- Index ---

    test "index renders annotations" do
      get rails_markup.root_path
      assert_response :success
    end

    test "index filters by status" do
      get rails_markup.root_path(status: "resolved")
      assert_response :success
    end

    test "index filters by page_url" do
      get rails_markup.root_path(page_url: "/sites/inventlist")
      assert_response :success
    end

    test "index with status=all shows everything" do
      get rails_markup.root_path(status: "all")
      assert_response :success
    end

    test "index defaults to pending status" do
      get rails_markup.root_path
      assert_select ".rm-pill-active", text: "Pending"
    end

    test "index renders turbo frames" do
      get rails_markup.root_path
      assert_select "turbo-frame#annotations-content"
      assert_select "turbo-frame#detail-panel"
    end

    # --- Show ---

    test "show displays annotation" do
      get rails_markup.annotation_path(annotations(:pending_fix))
      assert_response :success
    end

    test "show displays resolved annotation with thread" do
      get rails_markup.annotation_path(annotations(:resolved_fix))
      assert_response :success
    end

    test "show renders within detail-panel turbo frame" do
      get rails_markup.annotation_path(annotations(:pending_fix))
      assert_select "turbo-frame#detail-panel"
    end

    # --- Update actions ---

    test "acknowledge transitions and redirects" do
      annotation = annotations(:pending_fix)

      patch rails_markup.annotation_path(annotation), params: { action_type: "acknowledge" }

      assert_redirected_to rails_markup.annotation_path(annotation)
      assert_equal "acknowledged", annotation.reload.status
    end

    test "resolve with summary transitions and adds thread" do
      annotation = annotations(:pending_fix)

      patch rails_markup.annotation_path(annotation),
        params: { action_type: "resolve", summary: "Fixed the padding" }

      assert_redirected_to rails_markup.annotation_path(annotation)
      annotation.reload
      assert_equal "resolved", annotation.status
      assert_equal "Fixed the padding", annotation.thread.last["message"]
    end

    test "dismiss with reason transitions and adds thread" do
      annotation = annotations(:pending_fix)

      patch rails_markup.annotation_path(annotation),
        params: { action_type: "dismiss", reason: "Not a bug" }

      assert_redirected_to rails_markup.annotation_path(annotation)
      assert_equal "dismissed", annotation.reload.status
    end

    test "reply adds thread entry" do
      annotation = annotations(:pending_fix)

      patch rails_markup.annotation_path(annotation),
        params: { action_type: "reply", message: "Working on it", role: "agent" }

      assert_redirected_to rails_markup.annotation_path(annotation)
      annotation.reload
      assert_equal 1, annotation.thread.size
      assert_equal "Working on it", annotation.thread.last["message"]
      assert_equal "agent", annotation.thread.last["role"]
    end

    test "reply defaults role to agent" do
      annotation = annotations(:pending_fix)

      patch rails_markup.annotation_path(annotation),
        params: { action_type: "reply", message: "Noted" }

      assert_equal "agent", annotation.reload.thread.last["role"]
    end

    # --- Dismiss all ---

    test "dismiss_all dismisses pending annotations" do
      assert annotations(:pending_fix).status == "pending"

      post rails_markup.dismiss_all_path(status: "pending")

      assert_redirected_to rails_markup.root_path(status: "dismissed")
      assert_equal "dismissed", annotations(:pending_fix).reload.status
    end
  end
end

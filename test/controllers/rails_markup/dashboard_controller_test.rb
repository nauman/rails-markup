# frozen_string_literal: true

require_relative "../../engine_test_helper"

module RailsMarkup
  class DashboardControllerTest < ActionDispatch::IntegrationTest
    # --- Auth gating ---

    test "index renders when auth passes" do
      get rails_markup.root_path
      assert_response :success
    end

    test "index returns 403 when auth fails" do
      with_auth_check(->(_) { false }) do
        get rails_markup.root_path
        assert_response :forbidden
      end
    end

    test "show returns 403 when auth fails" do
      with_auth_check(->(_) { false }) do
        get rails_markup.annotation_path(annotations(:pending_fix))
        assert_response :forbidden
      end
    end

    # --- Index filtering ---

    test "index shows all annotations by default" do
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

    # --- Show ---

    test "show displays annotation" do
      get rails_markup.annotation_path(annotations(:pending_fix))
      assert_response :success
    end

    test "show displays resolved annotation with thread" do
      get rails_markup.annotation_path(annotations(:resolved_fix))
      assert_response :success
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

    private

    def with_auth_check(check)
      original = RailsMarkup.config.auth_check
      RailsMarkup.config.auth_check = check
      yield
    ensure
      RailsMarkup.config.auth_check = original
    end
  end
end

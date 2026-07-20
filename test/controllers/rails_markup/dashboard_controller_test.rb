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

    test "index with search query filters results" do
      get rails_markup.root_path(status: "all", q: "padding")
      assert_response :success
    end

    test "index with author filter" do
      Annotation.create!(content: "Test", page_url: "/t", metadata: { "author" => "TestAuthor" })

      get rails_markup.root_path(status: "all", author: "TestAuthor")
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

    test "show renders within detail-panel turbo frame" do
      get rails_markup.annotation_path(annotations(:pending_fix))
      assert_select "turbo-frame#detail-panel"
    end

    # --- Board ---

    test "board renders all columns" do
      get rails_markup.board_path
      assert_response :success
      assert_select ".rm-board-column", 4
    end

    test "board cards include a status select as a touch fallback" do
      get rails_markup.board_path
      assert_response :success
      # One move-select per rendered card (drag-and-drop alternative for touch).
      assert_select ".rm-board-card .rm-board-move"
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

    test "transition updates status via JSON" do
      annotation = annotations(:pending_fix)

      patch rails_markup.annotation_path(annotation),
        params: { action_type: "transition", status: "acknowledged" },
        as: :json

      assert_response :ok
      assert_equal "acknowledged", annotation.reload.status
    end

    test "transition with invalid status returns error" do
      annotation = annotations(:pending_fix)

      patch rails_markup.annotation_path(annotation),
        params: { action_type: "transition", status: "invalid" },
        as: :json

      assert_response :unprocessable_entity
    end

    # --- Dismiss all ---

    test "dismiss_all dismisses pending annotations" do
      assert annotations(:pending_fix).status == "pending"

      post rails_markup.dismiss_all_path(status: "pending")

      assert_redirected_to rails_markup.root_path(status: "dismissed")
      assert_equal "dismissed", annotations(:pending_fix).reload.status
    end

    # --- Export ---

    test "export_csv returns CSV file" do
      get rails_markup.export_csv_path
      assert_response :success
      assert_equal "text/csv", response.media_type
      assert response.body.include?("id,status,intent")
    end

    test "export_json returns JSON file" do
      get rails_markup.export_json_path
      assert_response :success
      assert_equal "application/json", response.media_type
      data = JSON.parse(response.body)
      assert data.is_a?(Array)
      assert data.first.key?("id")
    end

    # --- Load more ---

    test "load_more returns cards without layout" do
      get rails_markup.load_more_path(status: "all", page: 1)
      assert_response :success
      # Should not contain full HTML layout
      refute_match(/<html/, response.body)
    end

    test "load_more respects status filter" do
      get rails_markup.load_more_path(status: "pending", page: 1)
      assert_response :success
    end

    test "index and load_more use a keyset cursor for tied timestamps without overlap" do
      original_per_page = RailsMarkup.config.per_page
      RailsMarkup.config.per_page = 2
      timestamp = Time.current.change(usec: 0)
      records = 4.times.map do |i|
        Annotation.create!(content: "Tied #{i}", page_url: "/tied-pagination", created_at: timestamp, updated_at: timestamp)
      end

      get rails_markup.root_path(status: "all", page_url: "/tied-pagination")
      first_page_ids = css_select(".rm-card").map { |card| card["data-annotation-id"].to_i }
      # Follow the real cursor link the button carries (not a page number)
      next_url = css_select(".rm-load-more-btn").first["data-next-url"]

      get next_url
      second_page_ids = css_select(".rm-card").map { |card| card["data-annotation-id"].to_i }

      assert_equal records.map(&:id).reverse, first_page_ids + second_page_ids
      assert_empty first_page_ids & second_page_ids
    ensure
      RailsMarkup.config.per_page = original_per_page
    end

    test "keyset load_more does not repeat a row when an annotation is inserted between pages" do
      original_per_page = RailsMarkup.config.per_page
      RailsMarkup.config.per_page = 2
      base = Time.current.change(usec: 0)
      4.times do |i|
        t = base + i
        Annotation.create!(content: "Row #{i}", page_url: "/concurrent", created_at: t, updated_at: t)
      end

      get rails_markup.root_path(status: "all", page_url: "/concurrent")
      first_ids = css_select(".rm-card").map { |c| c["data-annotation-id"].to_i }
      next_url = css_select(".rm-load-more-btn").first["data-next-url"]

      # A newer annotation arrives before "Load more" is clicked — with offset
      # pagination this shifts the window and repeats a boundary row.
      newer = base + 10
      Annotation.create!(content: "Inserted", page_url: "/concurrent", created_at: newer, updated_at: newer)

      get next_url
      second_ids = css_select(".rm-card").map { |c| c["data-annotation-id"].to_i }

      assert_empty first_ids & second_ids,
                   "cursor page must not repeat a first-page row after a concurrent insert"
    ensure
      RailsMarkup.config.per_page = original_per_page
    end

    test "load_more respects search and author filters" do
      Annotation.create!(content: "Searchable item", page_url: "/t", metadata: { "author" => "FilterAuthor" })

      get rails_markup.load_more_path(status: "all", q: "Searchable", author: "FilterAuthor", page: 1)
      assert_response :success
    end

    test "index shows remaining count and load_more follows the cursor" do
      # Create enough annotations to have multiple pages (per_page defaults to 25)
      30.times do |i|
        Annotation.create!(content: "Bulk annotation #{i}", page_url: "/bulk", status: "pending")
      end

      get rails_markup.root_path(status: "pending", page_url: "/bulk")
      assert_match(/remaining/, response.body)
      next_url = css_select(".rm-load-more-btn").first["data-next-url"]

      get next_url
      assert_response :success
    end

    test "load_more without a cursor returns an empty page (no page-one repeat)" do
      10.times do |i|
        Annotation.create!(content: "Item #{i}", page_url: "/nocursor", status: "pending")
      end

      get rails_markup.load_more_path(status: "pending", page_url: "/nocursor")
      assert_response :success
      assert_empty css_select(".rm-card"), "cursor-less load_more must not re-serve page one"
    end

    test "index no longer renders page-number pills" do
      get rails_markup.root_path(status: "all")
      assert_response :success
      # Old pagination pills used rm-pill class for page numbers
      # The filter pills still use rm-pill but page number pills should be gone
      refute_select ".rm-filters a.rm-pill", text: /^\d+$/
    end

    test "export_csv respects status filter" do
      get rails_markup.export_csv_path(status: "pending")
      assert_response :success
      # CSV should only contain pending annotations
      lines = response.body.split("\n")
      data_lines = lines[1..] # skip header
      data_lines.each do |line|
        assert_includes line, "pending"
      end
    end
  end
end

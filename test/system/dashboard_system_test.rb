# frozen_string_literal: true

require_relative "../application_system_test_case"

# The engine's own mounted interface at /feedback (list dashboard + board).
class DashboardSystemTest < ApplicationSystemTestCase
  setup do
    authenticate_rails_markup_admin
  end

  test "mounted dashboard renders and lists an annotation" do
    RailsMarkup::Annotation.create!(
      content: "Increase the padding here", page_url: "/host", status: "pending"
    )

    visit "/feedback?status=pending"

    assert_text "Increase the padding here"
  end

  test "mounted board renders four columns" do
    visit "/feedback/board"

    assert_selector ".rm-board-column", count: 4
  end
end

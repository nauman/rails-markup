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

  test "feedback opens contextually and secondary controls are disclosed" do
    RailsMarkup::Annotation.create!(content: "Review in context", page_url: "/host")
    visit "/feedback"
    assert_no_selector "#rm-page-filter"
    assert_no_selector "#rm-launcher-visibility"
    find(".rm-card-link", text: "Review in context").click
    assert_current_path "/feedback"
    assert_selector "dialog[open]", count: 1
    assert_selector "#detail-panel .rm-detail-content", text: "Review in context"
    assert_no_selector "#detail-panel .rm-detail-meta"
    find("#detail-panel .rm-context > summary", text: "Context & details").click
    assert_selector "#detail-panel .rm-detail-meta", text: "/host"
    find("#detail-panel .rm-back").click
    assert_no_selector "#detail-panel .rm-detail"
    assert_equal "rm-card-link", page.evaluate_script("document.activeElement.className")
  end

  test "list uses the shared modal for actions and keeps its filters" do
    annotation = RailsMarkup::Annotation.create!(content: "Shared modal feedback", page_url: "/host")
    visit "/feedback?status=all&q=Shared"
    find(".rm-card-link", text: annotation.content).click
    within("dialog[open]") { click_button "Acknowledge" }
    assert_selector "dialog[open] .rm-status-acknowledged"
    assert_current_path "/feedback?status=all&q=Shared"
    find("dialog[open] .rm-back").click
    assert_no_selector "dialog[open]"
    assert_current_path "/feedback?status=all&q=Shared"
    assert_selector ".rm-card .rm-row-status", text: "Acknowledged"
  end

  test "mounted board renders four columns" do
    visit "/feedback/board"

    assert_selector ".rm-board-column", count: 4
  end

  test "board cards open a modal and return focus on close or Escape" do
    annotation = RailsMarkup::Annotation.create!(content: "Review this board card", page_url: "/host")
    visit "/feedback/board"
    assert_no_selector ".rm-workspace-heading"
    assert_no_text "Open a card to review."
    find(".rm-board-help > summary").click
    assert_text "Open a card to review."
    find(".rm-board-help > summary").click
    card = ".rm-board-card[data-annotation-id='#{annotation.id}']"
    find("#{card} .rm-card-link").click
    assert_current_path "/feedback/board"
    assert_selector "dialog[open]", count: 1
    assert_selector "#detail-panel .rm-detail-content", text: annotation.content
    assert_no_selector "#detail-panel .rm-detail-meta"
    find("#detail-panel .rm-context > summary", text: "Context & details").click
    assert_selector "#detail-panel .rm-detail-meta", text: "/host"
    find("#detail-panel .rm-back").click
    assert_no_selector "#detail-panel .rm-detail"
    assert_equal "rm-card-link", page.evaluate_script("document.activeElement.className")
    find("#{card} .rm-card-link").click
    find("dialog[open] .rm-back").send_keys(:escape)
    assert_no_selector "dialog[open]"
    assert_equal "rm-card-link", page.evaluate_script("document.activeElement.className")
  end

  test "board feedback actions stay in the modal and reconcile columns on close" do
    annotation = RailsMarkup::Annotation.create!(content: "Acknowledge from modal", page_url: "/host")
    visit "/feedback/board"
    find(".rm-card-link", text: annotation.content).click
    within("dialog[open]") { click_button "Acknowledge" }
    assert_selector "dialog[open] .rm-status-acknowledged"
    assert_current_path "/feedback/board"
    find("dialog[open] .rm-back").click
    assert_no_selector "dialog[open]"
    assert_selector ".rm-board-column[data-status='acknowledged'] .rm-board-card[data-annotation-id='#{annotation.id}']"
  end

  test "board move disclosure updates the column and empty state" do
    annotation = RailsMarkup::Annotation.create!(content: "Move this board card", page_url: "/host")
    visit "/feedback/board"
    card = ".rm-board-card[data-annotation-id='#{annotation.id}']"
    assert_no_selector "#{card} .rm-board-move"
    find("#{card} summary", text: "Move").click
    find("#{card} .rm-board-move").select("Acknowledged")
    assert_selector ".rm-board-column[data-status='acknowledged'] #{card}"
    assert_selector ".rm-board-column[data-status='acknowledged'] .rm-tab-count", text: "1", exact_text: true
    assert_selector ".rm-board-column[data-status='pending'] .rm-tab-count", text: "0", exact_text: true
    assert_no_selector ".rm-board-column[data-status='acknowledged'] .rm-board-empty"
    assert_selector ".rm-board-column[data-status='pending'] .rm-board-empty"
    assert_current_path "/feedback/board"
    visit "/feedback/board"
    assert_selector ".rm-board-column[data-status='acknowledged'] #{card}"
  end

  test "page filter works in the standalone dashboard without Turbo" do
    RailsMarkup::Annotation.create!(content: "Host feedback", page_url: "/host")
    RailsMarkup::Annotation.create!(content: "Other feedback", page_url: "/other")

    visit "/feedback"
    find(".rm-options > summary").click
    select "/host", from: "rm-page-filter"

    assert_text "Host feedback"
    assert_no_text "Other feedback"
  end
end

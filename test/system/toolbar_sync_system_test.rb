# frozen_string_literal: true

require_relative "../application_system_test_case"

class ToolbarSyncSystemTest < ApplicationSystemTestCase
  setup do
    RailsMarkup.config.enable_screenshots = false
    authenticate_rails_markup_admin
  end

  test "browser and server converge in turbo host" do
    visit "/host"

    assert page.evaluate_script("Boolean(window.Turbo)"), "the host must load real Turbo before the toolbar"

    find("#rm-fab").click
    assert_selector '#rm-dock[data-state="expanded"]'
    find("#rm-fab").click
    assert_selector '#rm-dock[data-state="annotating"]'
    find(".host-para").click
    assert_selector "#rm-popup", visible: :visible

    fill_in "rm-popup-input", with: "Increase the spacing"
    click_button "Add"

    assert_annotation_saved("Increase the spacing")
    find("#rm-panel-toggle").click
    assert_selector "#rm-panel", visible: :visible
    annotation = RailsMarkup::Annotation.find_by!(content: "Increase the spacing")
    assert_equal "/host", annotation.page_url

    annotation.resolve!(summary: "Spacing updated on the server")
    # Await the async pull so the convergence assertions don't race a still-in-flight
    # (or no-op) fetch.
    page.evaluate_async_script(<<~JS)
      const done = arguments[0];
      Promise.resolve(window.RailsMarkupToolbar._pullAnnotations()).then(() => done(true)).catch(() => done(true));
    JS

    assert_selector "#rm-panel", visible: :visible
    assert_selector ".rm-card-body", text: "Increase the spacing"
    assert_selector "[data-status-id][value='resolved']", visible: :all
    assert_selector "[data-status-id][value='resolved'] + .rm-menu-btn .rm-menu-label", text: "Resolved"
    assert_text "Spacing updated on the server"
  end

  private

  def assert_annotation_saved(content)
    assert_no_selector ".rm-storage-error"

    Timeout.timeout(Capybara.default_max_wait_time) do
      sleep 0.05 until RailsMarkup::Annotation.exists?(content: content)
    end
  end
end

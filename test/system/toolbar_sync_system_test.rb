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
    # Wait for annotation mode to be active (the panel opens) before clicking the
    # target — otherwise the click can race mode activation on a cold start.
    assert_selector "#rm-panel", visible: :visible
    find(".host-para").click
    assert_selector "#rm-popup", visible: :visible

    fill_in "rm-popup-input", with: "Increase the spacing"
    click_button "Add"

    assert_annotation_saved("Increase the spacing")
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
    assert_selector "[data-status-id] option:checked", text: "Resolved"
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

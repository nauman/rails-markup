# frozen_string_literal: true

require_relative "../application_system_test_case"

class ToolbarSystemTest < ApplicationSystemTestCase
  test "injected FAB renders and toggles the panel on a host page" do
    visit "/host"

    assert_selector "#rm-toolbar-root", visible: :all
    fab = find("#rm-fab")
    assert fab.visible?, "FAB should be visible by default"

    # Panel hidden until the FAB is clicked.
    assert_selector "#rm-panel", visible: :hidden
    fab.click
    assert_selector "#rm-panel", visible: :visible
  end

  test "fab_visible = false hides the FAB but keeps the toolbar system" do
    RailsMarkup.config.fab_visible = false

    visit "/host"

    assert_selector "#rm-toolbar-root", visible: :all
    assert_selector "#rm-fab", visible: :hidden
  end

  test "toolbar_enabled = false renders no toolbar at all" do
    RailsMarkup.config.toolbar_enabled = false

    visit "/host"

    assert_no_selector "#rm-toolbar-root", visible: :all
    assert_selector "#host-page"
  end
end

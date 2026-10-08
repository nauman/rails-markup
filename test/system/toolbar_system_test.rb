# frozen_string_literal: true

require_relative "../application_system_test_case"

class ToolbarSystemTest < ApplicationSystemTestCase
  setup do
    authenticate_rails_markup_admin
  end

  test "compact FAB expands before entering annotation mode" do
    visit "/host"

    assert_selector "#rm-toolbar-root", visible: :all
    fab = find("#rm-fab")
    assert fab.visible?, "FAB should be visible by default"

    assert_selector "#rm-dock-controls", visible: :hidden
    # Expanding does not start annotation mode or open the panel.
    assert_selector "#rm-panel", visible: :hidden
    fab.click
    assert_selector '#rm-dock[data-state="expanded"]'
    assert_selector "#rm-panel", visible: :hidden
    fab.click
    assert_selector '#rm-dock[data-state="annotating"]'
    find("#rm-dock-close").click
    assert_selector '#rm-dock[data-state="expanded"]'
    find("#rm-panel-toggle").click
    assert_selector "#rm-panel", visible: :visible
    find("#rm-dock-close").click
    assert_selector '#rm-dock[data-state="collapsed"]'
    assert_selector "#rm-panel", visible: :hidden
  end

  test "fab_visible = false hides the FAB but keeps the toolbar system" do
    RailsMarkup.config.fab_visible = false

    visit "/host"

    assert_selector "#rm-toolbar-root", visible: :all
    assert_selector "#rm-fab", visible: :hidden
  end

  test "Dock and FAB accent update in settings and persists across dock states and reload" do
    visit "/host"
    find("#rm-fab").click
    find("#rm-settings-toggle").click
    assert_selector "#rm-panel h3", text: "Toolbar settings"
    assert_no_selector "#rm-panel-list"
    assert_selector '[role="switch"][aria-label="Show floating toolbar"]'
    find('[data-setting="accent"][data-value="emerald"]').click

    assert_selector "#rm-panel h3", text: "Toolbar settings"
    assert_selector '[data-setting="accent"][data-value="emerald"][aria-pressed="true"]'
    assert_fab_color "rgb(5, 150, 105)"
    find("#rm-dock-close").click
    assert_selector '#rm-dock[data-state="collapsed"]'
    find("#rm-fab").click
    assert_selector '#rm-dock[data-state="expanded"]'
    assert_fab_color "rgb(5, 150, 105)"
    find("#rm-fab").click
    assert_selector '#rm-dock[data-state="annotating"]'
    assert_fab_color "rgb(5, 150, 105)"

    visit "/host"
    assert_selector '#rm-dock[data-state="collapsed"]'
    assert_fab_color "rgb(5, 150, 105)"
  end

  test "toolbar_enabled = false renders no toolbar at all" do
    RailsMarkup.config.toolbar_enabled = false

    visit "/host"

    assert_no_selector "#rm-toolbar-root", visible: :all
    assert_selector "#host-page"
  end

  test "dashboard can hide and restore the launcher for this browser" do
    visit "/feedback"
    find(".rm-options > summary").click
    find("#rm-launcher-visibility").click
    assert_selector '#rm-launcher-visibility[aria-checked="false"]'
    visit "/host"
    assert_no_selector "#rm-fab"
    assert_no_selector "#rm-dock"
    assert_no_selector "#rm-settings-toggle"
    visit "/feedback"
    find(".rm-options > summary").click
    assert_selector '#rm-launcher-visibility[aria-checked="false"]'
    find("#rm-launcher-visibility").click
    visit "/host"
    assert_selector "#rm-fab"
  end

  test "image attachments preview and can be removed without losing feedback" do
    visit "/host"
    find("#rm-fab").click
    find("#rm-fab").click
    find("#host-page").click
    fill_in "rm-popup-input", with: "Keep this draft while attaching an image"
    find("#rm-image-options > summary").click
    assert_selector "#rm-attach-screen"
    attach_file "rm-screenshot-file", File.expand_path("../fixtures/files/screenshot.png", __dir__), make_visible: true
    assert_selector ".rm-drawing-container img"
    assert_selector '[data-draw="arrow"]'
    find("#rm-remove-screenshot").click
    assert_no_selector ".rm-drawing-container"
    assert_field "rm-popup-input", with: "Keep this draft while attaching an image"
  end

  test "native capture attaches a video frame and stops sharing before submission" do
    visit "/host"
    find("#rm-fab").click
    find("#rm-fab").click
    find("#host-page").click
    page.execute_script(<<~JS)
      navigator.mediaDevices.getDisplayMedia = async () => {
        const canvas = document.createElement("canvas");
        canvas.width = 320; canvas.height = 180;
        canvas.getContext("2d").fillRect(0, 0, 320, 180);
        const stream = canvas.captureStream(10);
        window.markupTestTrack = stream.getVideoTracks()[0];
        return stream;
      };
    JS
    find("#rm-image-options > summary").click
    find("#rm-attach-screen").click
    assert_selector ".rm-drawing-container img"
    assert_equal "ended", page.evaluate_script("window.markupTestTrack.readyState")
    fill_in "rm-popup-input", with: "Native image attachment"
    find("#rm-btn-submit").click
    Timeout.timeout(Capybara.default_max_wait_time) do
      sleep 0.05 until RailsMarkup::Annotation.exists?(content: "Native image attachment")
    end
    annotation = RailsMarkup::Annotation.find_by!(content: "Native image attachment")
    assert_match %r{\Adata:image/png;base64,}, annotation.metadata["screenshot"]
    visit "/feedback/annotations/#{annotation.id}"
    assert_selector 'img[alt="Element screenshot"]'
  end

  private

  def assert_fab_color(expected)
    find("#host-page").hover
    # Wait out the hover transition before checking the rendered color.
    assert_selector "#rm-fab"
    assert_equal expected, page.evaluate_script('getComputedStyle(document.getElementById("rm-dock")).backgroundColor')
    Timeout.timeout(Capybara.default_max_wait_time) do
      sleep 0.05 until page.evaluate_script('getComputedStyle(document.getElementById("rm-fab")).backgroundColor') == expected
    end
  end
end

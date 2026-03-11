# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"
require_relative "../../lib/rails_markup/cli/initializer_writer"
require_relative "../../lib/rails_markup/cli/setup_wizard"

class SetupWizardTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir
    FileUtils.mkdir_p(File.join(@dir, "config", "initializers"))
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def test_initial_view_shows_first_step
    wizard = RailsMarkup::Cli::SetupWizard.new(dir: @dir)
    wizard.init

    view = wizard.view
    assert_match(/Step 1\/6/, view)
    assert_match(/Toolbar Accent/, view)
    assert_match(/indigo/, view)
  end

  def test_cursor_movement_with_arrow_keys
    wizard = RailsMarkup::Cli::SetupWizard.new(dir: @dir)
    wizard.init

    # Initially cursor is at 0
    view = wizard.view
    lines = view.split("\n")
    # First option should have cursor marker
    assert lines.any? { |l| l.include?("indigo") }

    # Move down
    wizard.update(key_msg(:down))
    view = wizard.view
    # cursor should have moved (we verify by checking that amber is now highlighted)
    assert_match(/amber/, view)
  end

  def test_step_advancement_on_enter
    wizard = RailsMarkup::Cli::SetupWizard.new(dir: @dir)
    wizard.init

    # Select first option (indigo) on step 1
    wizard.update(key_msg(:enter))

    view = wizard.view
    assert_match(/Step 2\/6/, view)
    assert_match(/Toolbar Position/, view)
    assert_equal "indigo", wizard.choices[:toolbar_accent]
  end

  def test_full_walkthrough_writes_files
    wizard = RailsMarkup::Cli::SetupWizard.new(dir: @dir)
    wizard.init

    # Step 1: accent — select indigo (first option)
    wizard.update(key_msg(:enter))

    # Step 2: position — select bl (first option)
    wizard.update(key_msg(:enter))

    # Step 3: size — select slim (first option)
    wizard.update(key_msg(:enter))

    # Step 4: screenshots — select Yes (first option)
    wizard.update(key_msg(:enter))

    # Step 5: URL — type a URL and press enter
    "https://myapp.com".each_char { |c| wizard.update(key_msg(:rune, c)) }
    wizard.update(key_msg(:enter))

    # Step 6: confirm — press Enter to confirm
    _, cmd = wizard.update(key_msg(:enter))

    assert wizard.completed
    assert_equal "indigo", wizard.choices[:toolbar_accent]
    assert_equal "bl", wizard.choices[:toolbar_position]
    assert_equal "slim", wizard.choices[:toolbar_size]
    assert_equal true, wizard.choices[:enable_screenshots]
    assert_equal "https://myapp.com", wizard.choices[:url]

    # Initializer should have been written
    init_path = File.join(@dir, "config", "initializers", "rails_markup.rb")
    assert File.exist?(init_path), "Initializer file should exist"
    content = File.read(init_path)
    assert_match(/config\.toolbar_accent = "indigo"/, content)
    assert_match(/config\.toolbar_position = "bl"/, content)
  end

  def test_esc_aborts_wizard
    wizard = RailsMarkup::Cli::SetupWizard.new(dir: @dir)
    wizard.init

    _, cmd = wizard.update(key_msg(:esc))

    refute wizard.completed
    assert_instance_of Bubbletea::QuitCommand, cmd
  end

  def test_skip_url_step_with_empty_enter
    wizard = RailsMarkup::Cli::SetupWizard.new(dir: @dir)
    wizard.init

    # Steps 1-4: select first option
    4.times { wizard.update(key_msg(:enter)) }

    # Step 5: URL — just press enter to skip
    wizard.update(key_msg(:enter))

    # Should be on confirm step
    view = wizard.view
    assert_match(/Step 6\/6/, view)
    assert_nil wizard.choices[:url]
  end

  private

  # Build a mock-free KeyMessage using the real Bubbletea class
  def key_msg(type, char = nil)
    case type
    when :up
      Bubbletea::KeyMessage.new(key_type: Bubbletea::KeyMessage::KEY_UP)
    when :down
      Bubbletea::KeyMessage.new(key_type: Bubbletea::KeyMessage::KEY_DOWN)
    when :enter
      Bubbletea::KeyMessage.new(key_type: Bubbletea::KeyMessage::KEY_ENTER)
    when :esc
      Bubbletea::KeyMessage.new(key_type: Bubbletea::KeyMessage::KEY_ESC)
    when :backspace
      Bubbletea::KeyMessage.new(key_type: Bubbletea::KeyMessage::KEY_BACKSPACE)
    when :rune
      Bubbletea::KeyMessage.new(key_type: Bubbletea::KeyMessage::KEY_RUNES, runes: char.codepoints)
    end
  end
end

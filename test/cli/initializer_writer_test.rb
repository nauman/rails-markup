# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../../lib/rails_markup/cli/initializer_writer"

class InitializerWriterTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir
    @init_dir = File.join(@dir, "config", "initializers")
    FileUtils.mkdir_p(@init_dir)
    @init_path = File.join(@init_dir, "rails_markup.rb")
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def test_creates_new_initializer_when_none_exists
    writer = RailsMarkup::Cli::InitializerWriter.new(dir: @dir)
    writer.write(toolbar_accent: "amber", toolbar_position: "br")

    assert File.exist?(@init_path)
    content = File.read(@init_path)
    assert_match(/RailsMarkup\.configure/, content)
    assert_match(/config\.toolbar_accent = "amber"/, content)
    assert_match(/config\.toolbar_position = "br"/, content)
  end

  def test_updates_commented_lines
    File.write(@init_path, <<~RUBY)
      RailsMarkup.configure do |config|
        # config.toolbar_accent = "indigo"
        config.api_token = "secret"
      end
    RUBY

    writer = RailsMarkup::Cli::InitializerWriter.new(dir: @dir)
    writer.write(toolbar_accent: "rose")

    content = File.read(@init_path)
    assert_match(/config\.toolbar_accent = "rose"/, content)
    refute_match(/# config\.toolbar_accent/, content)
    assert_match(/config\.api_token = "secret"/, content)
  end

  def test_updates_uncommented_lines
    File.write(@init_path, <<~RUBY)
      RailsMarkup.configure do |config|
        config.toolbar_accent = "indigo"
        config.toolbar_position = "bl"
      end
    RUBY

    writer = RailsMarkup::Cli::InitializerWriter.new(dir: @dir)
    writer.write(toolbar_accent: "emerald", toolbar_position: "tr")

    content = File.read(@init_path)
    assert_match(/config\.toolbar_accent = "emerald"/, content)
    assert_match(/config\.toolbar_position = "tr"/, content)
    refute_match(/"indigo"/, content)
    refute_match(/"bl"/, content)
  end

  def test_appends_missing_keys_before_end
    File.write(@init_path, <<~RUBY)
      RailsMarkup.configure do |config|
        config.api_token = "secret"
      end
    RUBY

    writer = RailsMarkup::Cli::InitializerWriter.new(dir: @dir)
    writer.write(toolbar_size: "compact", enable_screenshots: false)

    content = File.read(@init_path)
    assert_match(/config\.toolbar_size = "compact"/, content)
    assert_match(/config\.enable_screenshots = false/, content)
    assert_match(/config\.api_token = "secret"/, content)
    # Keys should appear before the closing end
    end_pos = content.index(/^end/)
    size_pos = content.index(/config\.toolbar_size/)
    assert size_pos < end_pos, "New keys should appear before 'end'"
  end

  def test_preserves_unrelated_config_lines
    File.write(@init_path, <<~RUBY)
      RailsMarkup.configure do |config|
        config.api_token = ENV["RAILS_MARKUP_API_TOKEN"]
        config.base_controller_class = "Admin::BaseController"
        config.per_page = 50
      end
    RUBY

    writer = RailsMarkup::Cli::InitializerWriter.new(dir: @dir)
    writer.write(toolbar_accent: "blue")

    content = File.read(@init_path)
    assert_match(/config\.api_token = ENV/, content)
    assert_match(/config\.base_controller_class = "Admin::BaseController"/, content)
    assert_match(/config\.per_page = 50/, content)
    assert_match(/config\.toolbar_accent = "blue"/, content)
  end
end

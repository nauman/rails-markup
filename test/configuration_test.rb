# frozen_string_literal: true

require_relative "engine_test_helper"

class ConfigurationTest < ActiveSupport::TestCase
  test "defaults base_controller_class to engine's ApplicationController" do
    config = RailsMarkup::Configuration.new
    assert_equal "RailsMarkup::ApplicationController", config.base_controller_class
  end

  test "defaults table_name to rails_markup_annotations" do
    config = RailsMarkup::Configuration.new
    assert_equal "rails_markup_annotations", config.table_name
  end

  test "defaults per_page to 25" do
    config = RailsMarkup::Configuration.new
    assert_equal 25, config.per_page
  end

  test "defaults toolbar_accent to indigo" do
    config = RailsMarkup::Configuration.new
    assert_equal "indigo", config.toolbar_accent
  end

  test "defaults api_token to nil" do
    config = RailsMarkup::Configuration.new
    assert_nil config.api_token
  end

  test "configure block sets values" do
    original_accent = RailsMarkup.config.toolbar_accent

    RailsMarkup.configure do |config|
      config.toolbar_accent = "amber"
    end

    assert_equal "amber", RailsMarkup.config.toolbar_accent
  ensure
    RailsMarkup.config.toolbar_accent = original_accent
  end

  test "config is accessible via shorthand" do
    assert_equal RailsMarkup.configuration, RailsMarkup.config
  end

  test "base_controller_class accepts string" do
    config = RailsMarkup::Configuration.new
    config.base_controller_class = "ActionController::Base"
    assert_equal "ActionController::Base", config.base_controller_class
  end

  test "defaults return_url to nil" do
    config = RailsMarkup::Configuration.new
    assert_nil config.return_url
  end

  test "return_url accepts path string" do
    config = RailsMarkup::Configuration.new
    config.return_url = "/admin"
    assert_equal "/admin", config.return_url
  end

  # --- Author name method ---

  test "defaults author_name_method to :email" do
    config = RailsMarkup::Configuration.new
    assert_equal :email, config.author_name_method
  end

  test "resolve_author_name with symbol method" do
    config = RailsMarkup::Configuration.new
    config.author_name_method = :name
    user = Struct.new(:name).new("Alice")
    assert_equal "Alice", config.resolve_author_name(user)
  end

  test "resolve_author_name with proc" do
    config = RailsMarkup::Configuration.new
    config.author_name_method = ->(u) { "#{u.first} #{u.last}" }
    user = Struct.new(:first, :last).new("Alice", "Smith")
    assert_equal "Alice Smith", config.resolve_author_name(user)
  end

  test "resolve_author_name returns nil for nil user" do
    config = RailsMarkup::Configuration.new
    assert_nil config.resolve_author_name(nil)
  end

  test "resolve_author_name returns nil when method not found" do
    config = RailsMarkup::Configuration.new
    config.author_name_method = :nonexistent_method
    user = Struct.new(:email).new("test@example.com")
    assert_nil config.resolve_author_name(user)
  end

  test "resolve_author_name rescues errors from proc" do
    config = RailsMarkup::Configuration.new
    config.author_name_method = ->(_u) { raise "boom" }
    user = Struct.new(:email).new("test@example.com")
    assert_nil config.resolve_author_name(user)
  end

  # --- Notification hook ---

  test "defaults on_create_callback to nil" do
    config = RailsMarkup::Configuration.new
    assert_nil config.on_create_callback
  end

  test "on_create_callback accepts proc" do
    config = RailsMarkup::Configuration.new
    callback = ->(ann) { ann }
    config.on_create_callback = callback
    assert_equal callback, config.on_create_callback
  end

  # --- Screenshots ---

  test "defaults enable_screenshots to true" do
    config = RailsMarkup::Configuration.new
    assert config.enable_screenshots
  end

  test "enable_screenshots can be disabled" do
    config = RailsMarkup::Configuration.new
    config.enable_screenshots = false
    assert_not config.enable_screenshots
  end

  # --- Toolbar position ---

  test "defaults toolbar_position to bl" do
    config = RailsMarkup::Configuration.new
    assert_equal "bl", config.toolbar_position
  end

  test "toolbar_position accepts valid positions" do
    config = RailsMarkup::Configuration.new
    %w[tl tr br bl].each do |pos|
      config.toolbar_position = pos
      assert_equal pos, config.toolbar_position
    end
  end

  test "toolbar_position rejects invalid value" do
    config = RailsMarkup::Configuration.new
    assert_raises(ArgumentError) { config.toolbar_position = "center" }
  end

  # --- Toolbar size ---

  test "defaults toolbar_size to default" do
    config = RailsMarkup::Configuration.new
    assert_equal "default", config.toolbar_size
  end

  test "toolbar_size accepts valid sizes" do
    config = RailsMarkup::Configuration.new
    %w[slim compact default].each do |size|
      config.toolbar_size = size
      assert_equal size, config.toolbar_size
    end
  end

  test "toolbar_size rejects invalid value" do
    config = RailsMarkup::Configuration.new
    assert_raises(ArgumentError) { config.toolbar_size = "huge" }
  end
end

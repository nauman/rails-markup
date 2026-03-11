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
end

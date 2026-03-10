# frozen_string_literal: true

require_relative "../engine_test_helper"
require "generators/rails_markup/install_generator"

class InstallGeneratorTest < ActiveSupport::TestCase
  test "generator class is defined" do
    assert defined?(RailsMarkup::Generators::InstallGenerator)
  end

  test "generator inherits from Rails::Generators::Base" do
    assert RailsMarkup::Generators::InstallGenerator < Rails::Generators::Base
  end

  test "generator includes migration support" do
    assert RailsMarkup::Generators::InstallGenerator.included_modules.any? { |m| m.name&.include?("Migration") }
  end

  test "migration template exists" do
    template_path = File.expand_path(
      "../../lib/generators/rails_markup/install/templates/create_rails_markup_annotations.rb.erb",
      __dir__
    )
    assert File.exist?(template_path), "Migration template should exist at #{template_path}"
  end

  test "initializer template exists" do
    template_path = File.expand_path(
      "../../lib/generators/rails_markup/install/templates/initializer.rb.erb",
      __dir__
    )
    assert File.exist?(template_path), "Initializer template should exist at #{template_path}"
  end

  test "migration template contains correct schema" do
    template_path = File.expand_path(
      "../../lib/generators/rails_markup/install/templates/create_rails_markup_annotations.rb.erb",
      __dir__
    )
    content = File.read(template_path)

    assert_match(/page_url/, content)
    assert_match(/content/, content)
    assert_match(/intent/, content)
    assert_match(/severity/, content)
    assert_match(/status/, content)
    assert_match(/thread/, content)
    assert_match(/target/, content)
    assert_match(/metadata/, content)
  end

  test "initializer template contains config options" do
    template_path = File.expand_path(
      "../../lib/generators/rails_markup/install/templates/initializer.rb.erb",
      __dir__
    )
    content = File.read(template_path)

    assert_match(/RailsMarkup\.configure/, content)
    assert_match(/base_controller_class/, content)
    assert_match(/api_token/, content)
    assert_match(/table_name/, content)
    assert_match(/per_page/, content)
    assert_match(/toolbar_accent/, content)
  end
end

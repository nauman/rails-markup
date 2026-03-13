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

  # -- Class options --

  test "mount_path option defaults to /admin/annotations" do
    opt = RailsMarkup::Generators::InstallGenerator.class_options[:mount_path]
    assert_equal "/admin/annotations", opt.default
  end

  test "base_controller option defaults to ApplicationController" do
    opt = RailsMarkup::Generators::InstallGenerator.class_options[:base_controller]
    assert_equal "ApplicationController", opt.default
  end

  test "layout option defaults to application" do
    opt = RailsMarkup::Generators::InstallGenerator.class_options[:layout]
    assert_equal "application", opt.default
  end

  # -- Templates exist --

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

  test "auth controller template exists" do
    template_path = File.expand_path(
      "../../lib/generators/rails_markup/install/templates/auth_controller.rb.erb",
      __dir__
    )
    assert File.exist?(template_path), "Auth controller template should exist at #{template_path}"
  end

  test "bin wrapper template exists" do
    template_path = File.expand_path(
      "../../lib/generators/rails_markup/install/templates/bin_markup.erb",
      __dir__
    )
    assert File.exist?(template_path), "Bin wrapper template should exist at #{template_path}"
  end

  # -- Template content --

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

  test "initializer template sets base_controller_class to RailsMarkupAuthController" do
    template_path = File.expand_path(
      "../../lib/generators/rails_markup/install/templates/initializer.rb.erb",
      __dir__
    )
    content = File.read(template_path)

    assert_match(/config\.base_controller_class = "RailsMarkupAuthController"/, content)
  end

  test "auth controller template uses base_controller option" do
    template_path = File.expand_path(
      "../../lib/generators/rails_markup/install/templates/auth_controller.rb.erb",
      __dir__
    )
    content = File.read(template_path)

    assert_match(/RailsMarkupAuthController/, content)
    assert_match(/options\[:base_controller\]/, content)
  end

  # -- Procfile.dev injection --

  test "generator defines inject_procfile method" do
    generator = RailsMarkup::Generators::InstallGenerator.new
    assert generator.respond_to?(:inject_procfile),
      "InstallGenerator should define inject_procfile method"
  end
end

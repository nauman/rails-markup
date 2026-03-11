# frozen_string_literal: true

require_relative "../engine_test_helper"
require "generators/rails_markup/uninstall_generator"

class UninstallGeneratorTest < ActiveSupport::TestCase
  test "generator class is defined" do
    assert defined?(RailsMarkup::Generators::UninstallGenerator)
  end

  test "generator inherits from Rails::Generators::Base" do
    assert RailsMarkup::Generators::UninstallGenerator < Rails::Generators::Base
  end

  test "remove_migration option defaults to false" do
    opt = RailsMarkup::Generators::UninstallGenerator.class_options[:remove_migration]
    assert_equal false, opt.default
  end

  test "remove_migration option is boolean type" do
    opt = RailsMarkup::Generators::UninstallGenerator.class_options[:remove_migration]
    assert_equal :boolean, opt.type
  end

  test "generator defines expected public methods" do
    instance_methods = RailsMarkup::Generators::UninstallGenerator.public_instance_methods(false)
    expected = %i[remove_route_mount remove_initializer remove_auth_controller
                  remove_toolbar_from_layouts remove_bin_wrapper remove_migration
                  show_post_uninstall]

    expected.each do |method_name|
      assert_includes instance_methods, method_name, "Expected public method: #{method_name}"
    end
  end
end

# frozen_string_literal: true

require_relative "boot"

require "rails"
require "active_model/railtie"
require "active_record/railtie"
require "action_controller/railtie"
require "action_view/railtie"

Bundler.require(*Rails.groups)
require "rails_markup"

module Dummy
  class Application < Rails::Application
    config.root = File.expand_path("../..", __FILE__)
    config.load_defaults Rails::VERSION::STRING.to_f
    config.eager_load = false
    config.secret_key_base = "test-secret-key-for-rails-markup-engine"
  end
end

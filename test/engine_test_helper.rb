# frozen_string_literal: true

ENV["RAILS_ENV"] = "test"

require_relative "dummy/config/environment"
require "rails/test_help"
require "minitest/autorun"

# Load the schema
ActiveRecord::Schema.verbose = false
load File.expand_path("dummy/db/schema.rb", __dir__)

class ActiveSupport::TestCase
  def create_annotation!(attrs = {})
    RailsMarkup::Annotation.create!({
      page_url: "/test/page",
      content: "Fix this element",
      intent: "change",
      severity: "suggestion",
      status: "pending",
      target: {},
      metadata: {},
      thread: []
    }.merge(attrs))
  end
end

class ActionDispatch::IntegrationTest
  include RailsMarkup::Engine.routes.url_helpers

  def default_url_options
    { host: "test.host" }
  end
end

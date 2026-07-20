# frozen_string_literal: true

ENV["RAILS_ENV"] = "test"

require_relative "dummy/config/environment"
require "rails/test_help"
require "minitest/autorun"

# Load the schema
ActiveRecord::Schema.verbose = false
load File.expand_path("dummy/db/schema.rb", __dir__)

class ActiveSupport::TestCase
  self.fixture_paths = [File.expand_path("fixtures", __dir__)]
  set_fixture_class rails_markup_annotations: RailsMarkup::Annotation
  fixtures :rails_markup_annotations

  private

  # Access fixtures by name — returns RailsMarkup::Annotation instances
  def annotations(name)
    rails_markup_annotations(name)
  end
end

class ActionDispatch::IntegrationTest
  include RailsMarkup::Engine.routes.url_helpers

  def authenticate_rails_markup_admin
    get "/rails_markup_test_session/new"
    token = response.body.match(/name="authenticity_token" value="([^"]+)"/).captures.first
    post "/rails_markup_test_session", params: { authenticity_token: token }
    token
  end

  def default_url_options
    { host: "test.host" }
  end
end

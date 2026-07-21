# frozen_string_literal: true

ENV["RAILS_ENV"] = "test"

require_relative "dummy/config/environment"
require "rails/test_help"
require "minitest/autorun"
require "capybara/minitest"
require "capybara/cuprite"
require "minitest/retry"

# Browser tests are inherently prone to rare cold-start/timing flakes. Retry a
# failed system test before reporting red, so CI stays reliable. This is loaded
# only by the system suite (not the default `rake test`), so unit tests never retry.
Minitest::Retry.use!(retry_count: 2, verbose: true)

# System tests run a real Capybara server in a background thread. ":memory:"
# SQLite is per-connection, so the server thread would see no schema/rows —
# point the whole process at a shared file DB instead.
SYSTEM_TEST_DB = File.expand_path("dummy/db/system_test.sqlite3", __dir__)
File.delete(SYSTEM_TEST_DB) if File.exist?(SYSTEM_TEST_DB)
ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: SYSTEM_TEST_DB)
ActiveRecord::Schema.verbose = false
load File.expand_path("dummy/db/schema.rb", __dir__)

Capybara.register_driver(:cuprite) do |app|
  Capybara::Cuprite::Driver.new(
    app,
    window_size: [1200, 800],
    headless: true,
    process_timeout: 30,
    browser_options: { "no-sandbox" => nil }
  )
end

Capybara.default_driver    = :cuprite
Capybara.javascript_driver = :cuprite
Capybara.app = Rails.application
Capybara.server = :puma, { Silent: true }
Capybara.default_max_wait_time = 5

class ApplicationSystemTestCase < ActiveSupport::TestCase
  include Capybara::DSL
  include Capybara::Minitest::Assertions

  # Real server thread shares our DB connection, so transactions can't isolate
  # test data — clean up explicitly instead.
  self.use_transactional_tests = false

  def authenticate_rails_markup_admin
    visit "/rails_markup_test_session/new"
    click_button "Authenticate"
  end

  teardown do
    RailsMarkup::Annotation.delete_all
    Capybara.reset_sessions!
    RailsMarkup.reset_configuration!
  end
end

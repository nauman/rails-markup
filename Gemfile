# frozen_string_literal: true

source "https://rubygems.org"

gemspec

group :test do
  gem "minitest", "~> 5.0"
  gem "rake", "~> 13.0"
  gem "rails", ">= 7.0"
  gem "sqlite3"
  # Browser/system tests (opt-in via `rake test:system`; needs Chrome).
  gem "capybara", "~> 3.40"
  gem "cuprite", "~> 0.15"
  gem "puma", "~> 6.0"
  gem "minitest-retry", "~> 0.2" # retry inherently-flaky browser tests (system only)
end

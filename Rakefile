# frozen_string_literal: true

require "bundler/gem_tasks"
require "rake/testtask"

# Default suite excludes browser/system tests (those need Chrome).
Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/**/*_test.rb"].exclude("test/system/**/*")
end

namespace :test do
  desc "Run browser/system tests (requires Chrome/Chromium)"
  Rake::TestTask.new(:system) do |t|
    t.libs << "test"
    t.libs << "lib"
    t.test_files = FileList["test/system/**/*_test.rb"]
  end
end

task default: :test

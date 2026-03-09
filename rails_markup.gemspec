# frozen_string_literal: true

require_relative "lib/rails_markup/version"

Gem::Specification.new do |spec|
  spec.name          = "rails-markup"
  spec.version       = RailsMarkup::VERSION
  spec.authors       = ["InventList"]
  spec.email         = ["hello@inventlist.com"]

  spec.summary       = "Point-and-click annotation tool for AI agents"
  spec.description   = "An MCP server that lets you annotate Rails views in the browser and have AI agents read and act on your feedback."
  spec.homepage      = "https://github.com/inventlist/rails-markup"
  spec.license       = "MIT"

  spec.required_ruby_version = ">= 3.1"

  spec.files = Dir[
    "lib/**/*.rb",
    "lib/**/*.erb",
    "app/**/*.rb",
    "app/**/*.erb",
    "app/**/*.js",
    "config/**/*.rb",
    "bin/*",
    "README.md",
    "LICENSE"
  ]
  spec.bindir        = "bin"
  spec.executables   = ["rails-markup"]

  spec.add_dependency "webrick", "~> 1.8"
  spec.add_dependency "railties", ">= 7.0"
  spec.add_dependency "activerecord", ">= 7.0"

  spec.metadata["homepage_uri"]    = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"]   = "#{spec.homepage}/blob/main/CHANGELOG.md"
end

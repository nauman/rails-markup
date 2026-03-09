# frozen_string_literal: true

require_relative "rails_markup/version"
require_relative "rails_markup/configuration"
require_relative "rails_markup/store"
require_relative "rails_markup/http_store_proxy"
require_relative "rails_markup/http_server"
require_relative "rails_markup/mcp_server"
require_relative "rails_markup/server"

require_relative "rails_markup/engine" if defined?(Rails::Engine)

# frozen_string_literal: true

module RailsMarkup
  class Configuration
    # Lambda called with controller instance to check authorization.
    # Default: always allow (override in initializer).
    # Example: ->(controller) { controller.current_user&.admin? }
    attr_accessor :auth_check

    # Bearer token for the external API (MCP production tools).
    # Set to nil to disable external API.
    attr_accessor :api_token

    # Database table name for annotations.
    attr_accessor :table_name

    # Number of annotations per page on the dashboard.
    attr_accessor :per_page

    # Accent color for the toolbar FAB and UI elements.
    # Accepts: "indigo", "amber", "blue", "emerald", "rose"
    attr_accessor :toolbar_accent

    def initialize
      @auth_check = ->(_controller) { true }
      @api_token = nil
      @table_name = "rails_markup_annotations"
      @per_page = 25
      @toolbar_accent = "indigo"
    end
  end

  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    alias_method :config, :configuration

    def configure
      yield(configuration)
    end

    def reset_configuration!
      @configuration = Configuration.new
    end
  end
end

# frozen_string_literal: true

module RailsMarkup
  class Configuration
    ALLOWED_ACCENTS = %w[indigo amber blue emerald rose].freeze

    # Base controller class name for dashboard/API controllers.
    # Set to a controller that provides authentication.
    # Example: "AdminAuthController"
    attr_accessor :base_controller_class

    # Bearer token for the external API (MCP production tools).
    # Set to nil to disable external API.
    attr_accessor :api_token

    # Database table name for annotations.
    attr_accessor :table_name

    # Accent color for the toolbar FAB and UI elements.
    attr_reader :toolbar_accent

    # URL path for "Back to app" link in the dashboard header.
    # Set to nil to hide the link.
    # Example: "/admin"
    attr_accessor :return_url

    # Layout for the dashboard views.
    # Set to a host app layout name to embed within that layout.
    # Default: "rails_markup/application" (engine's own layout)
    # Example: "admin"
    attr_accessor :dashboard_layout

    # Number of annotations per page on the dashboard.
    attr_reader :per_page

    def initialize
      @base_controller_class = "RailsMarkup::ApplicationController"
      @api_token = nil
      @table_name = "rails_markup_annotations"
      @per_page = 25
      @toolbar_accent = "indigo"
      @return_url = nil
      @dashboard_layout = "rails_markup/application"
    end

    def per_page=(value)
      raise ArgumentError, "per_page must be a positive integer" unless value.is_a?(Integer) && value.positive?

      @per_page = value
    end

    def toolbar_accent=(value)
      unless ALLOWED_ACCENTS.include?(value.to_s)
        raise ArgumentError, "toolbar_accent must be one of: #{ALLOWED_ACCENTS.join(', ')}"
      end

      @toolbar_accent = value.to_s
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

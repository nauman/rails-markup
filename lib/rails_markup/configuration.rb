# frozen_string_literal: true

module RailsMarkup
  class Configuration
    ALLOWED_ACCENTS   = %w[indigo amber blue emerald rose].freeze
    ALLOWED_POSITIONS = %w[tl tr br bl].freeze
    ALLOWED_SIZES     = %w[slim compact default].freeze

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

    # Method name (Symbol) or Proc to resolve the author's display name from the current_user.
    # Symbol: calls user.public_send(method_name) — e.g. :name, :email, :display_name
    # Proc: receives user, returns string — e.g. ->(u) { u.full_name }
    # Default: :email
    attr_accessor :author_name_method

    # Proc called after an annotation is created. Receives the annotation record.
    # Use for email/Slack/webhook notifications.
    # Default: nil (no callback)
    attr_accessor :on_create_callback

    # Enable element screenshot capture in the toolbar.
    # Default: true
    attr_accessor :enable_screenshots

    # FAB button position: "bl" (bottom-left), "br" (bottom-right),
    # "tl" (top-left), "tr" (top-right). Default: "bl"
    attr_reader :toolbar_position

    # FAB button size: "default" (48px), "compact" (40px), "slim" (32px).
    # Default: "default"
    attr_reader :toolbar_size

    def initialize
      @base_controller_class = "RailsMarkup::ApplicationController"
      @api_token = nil
      @table_name = "rails_markup_annotations"
      @per_page = 25
      @toolbar_accent = "indigo"
      @toolbar_position = "bl"
      @toolbar_size = "default"
      @return_url = nil
      @dashboard_layout = "rails_markup/application"
      @author_name_method = :email
      @on_create_callback = nil
      @enable_screenshots = true
    end

    def resolve_author_name(user)
      return nil unless user

      case author_name_method
      when Symbol then user.respond_to?(author_name_method) ? user.public_send(author_name_method) : nil
      when Proc   then author_name_method.call(user)
      end
    rescue => e
      Rails.logger.warn("[rails-markup] author_name_method error: #{e.message}") if defined?(Rails)
      nil
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

    def toolbar_position=(value)
      unless ALLOWED_POSITIONS.include?(value.to_s)
        raise ArgumentError, "toolbar_position must be one of: #{ALLOWED_POSITIONS.join(', ')}"
      end

      @toolbar_position = value.to_s
    end

    def toolbar_size=(value)
      unless ALLOWED_SIZES.include?(value.to_s)
        raise ArgumentError, "toolbar_size must be one of: #{ALLOWED_SIZES.join(', ')}"
      end

      @toolbar_size = value.to_s
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

# frozen_string_literal: true

module RailsMarkup
  class DashboardController < RailsMarkup.config.base_controller_class.constantize
    layout -> { RailsMarkup.config.dashboard_layout }

    # When using a host app layout, expose host route helpers and all
    # view helpers (icon, super_admin?, etc.) so the layout renders correctly.
    if RailsMarkup.config.dashboard_layout != "rails_markup/application"
      base = RailsMarkup.config.base_controller_class.constantize
      helper base._helpers

      # Delegate unknown *_path/*_url helpers to main_app so host routes
      # don't get the engine mount prefix (/admin/annotations) prepended.
      host_routes = Module.new do
        def method_missing(method, *args, **kwargs, &block)
          if method.to_s.match?(/_(path|url)\z/) && main_app.respond_to?(method)
            main_app.public_send(method, *args, **kwargs, &block)
          else
            super
          end
        end

        def respond_to_missing?(method, include_private = false)
          (method.to_s.match?(/_(path|url)\z/) && main_app.respond_to?(method)) || super
        end
      end
      helper host_routes

      # Include helpers that gems add directly to ActionView::Base
      ActionView::Base.included_modules.each do |mod|
        next unless mod.is_a?(Module) && mod.name&.include?("Helper")
        next if mod.name.start_with?("RailsMarkup")
        helper mod rescue nil
      end
    end

    before_action :set_annotation, only: %i[show update]

    # GET /feedback
    def index
      status = params[:status] || "pending"
      scope = Annotation.recent
      scope = scope.where(status: status) unless status == "all"
      scope = scope.for_page(params[:page_url]) if params[:page_url].present?

      @current_page = (params[:page] || 1).to_i
      @annotations = scope.limit(per_page).offset((@current_page - 1) * per_page)

      @total_count = Annotation.count
      @pending_count = Annotation.pending.count
      @acknowledged_count = Annotation.acknowledged.count
      @resolved_count = Annotation.resolved.count
      @dismissed_count = Annotation.dismissed.count
      @page_urls = Annotation.distinct.pluck(:page_url).sort
      @current_status = params[:status] || "pending"
      @current_page_url = params[:page_url]
    end

    # GET /feedback/annotations/:id
    def show
    end

    # POST /feedback/dismiss_all
    def dismiss_all
      scope = Annotation.where(status: %w[pending acknowledged])
      scope = scope.where(status: params[:status]) if params[:status].present?
      count = scope.count
      scope.find_each { |a| a.dismiss!(reason: "Bulk dismissed") }
      redirect_to root_path(status: "dismissed"), notice: "#{count} annotations dismissed."
    end

    # PATCH /feedback/annotations/:id
    def update
      case params[:action_type]
      when "acknowledge" then @annotation.acknowledge!
      when "resolve"     then @annotation.resolve!(summary: params[:summary].presence)
      when "dismiss"     then @annotation.dismiss!(reason: params[:reason].presence)
      when "reply"       then @annotation.add_reply!(message: params[:message], role: params[:role] || "agent")
      end

      redirect_to annotation_path(@annotation), notice: "Annotation updated."
    end

    private

    def set_annotation
      @annotation = Annotation.find(params[:id])
    end

    def per_page
      RailsMarkup.config.per_page
    end
  end
end

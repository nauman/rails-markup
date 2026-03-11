# frozen_string_literal: true

require "csv"

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

    ALLOWED_STATUSES = %w[all pending acknowledged resolved dismissed].freeze
    ALLOWED_ROLES = %w[agent user].freeze

    before_action :set_annotation, only: %i[show update]

    # GET /feedback
    def index
      @current_status = ALLOWED_STATUSES.include?(params[:status]) ? params[:status] : "pending"
      base_scope = build_base_scope

      # Single grouped count query instead of 6 separate queries
      counts = base_scope.group(:status).count
      @total_count = counts.values.sum
      @pending_count = counts["pending"] || 0
      @acknowledged_count = counts["acknowledged"] || 0
      @resolved_count = counts["resolved"] || 0
      @dismissed_count = counts["dismissed"] || 0

      scope = base_scope.recent
      scope = scope.where(status: @current_status) unless @current_status == "all"
      scope = scope.search(params[:q]) if params[:q].present?
      scope = scope.by_author(params[:author]) if params[:author].present?

      # Use filtered count for pagination (not total)
      @filtered_count = scope.count
      @current_page = (params[:page] || 1).to_i
      @annotations = scope.limit(per_page).offset((@current_page - 1) * per_page)

      loaded_so_far = @current_page * per_page
      @remaining = [@filtered_count - loaded_so_far, 0].max
      @next_page = @remaining > 0 ? @current_page + 1 : nil

      @page_urls = Annotation.distinct.pluck(:page_url).sort
      @current_page_url = params[:page_url]
      @authors = Annotation.distinct_authors
      @current_author = params[:author]
      @current_query = params[:q]
    end

    # GET /feedback/annotations/:id
    def show
    end

    # GET /feedback/load_more
    def load_more
      @current_status = ALLOWED_STATUSES.include?(params[:status]) ? params[:status] : "pending"
      scope = build_base_scope.recent
      scope = scope.where(status: @current_status) unless @current_status == "all"
      scope = scope.search(params[:q]) if params[:q].present?
      scope = scope.by_author(params[:author]) if params[:author].present?

      filtered_count = scope.count
      @current_page = (params[:page] || 1).to_i
      @annotations = scope.limit(per_page).offset((@current_page - 1) * per_page)

      loaded_so_far = @current_page * per_page
      @remaining = [filtered_count - loaded_so_far, 0].max
      @next_page = @remaining > 0 ? @current_page + 1 : nil

      render partial: "annotation_page", layout: false
    end

    # GET /feedback/board
    def board
      @columns = {
        pending: Annotation.pending.recent.limit(50),
        acknowledged: Annotation.acknowledged.recent.limit(50),
        resolved: Annotation.resolved.recent.limit(20),
        dismissed: Annotation.dismissed.recent.limit(20)
      }
    end

    # POST /feedback/dismiss_all
    def dismiss_all
      status = params[:status]
      unless status.in?(%w[pending acknowledged])
        return redirect_to root_path, alert: "Invalid status for bulk dismiss."
      end

      count = Annotation.where(status: status).update_all(status: "dismissed")
      redirect_to root_path(status: "dismissed"), notice: "#{count} annotations dismissed."
    end

    # PATCH /feedback/annotations/:id
    def update
      case params[:action_type]
      when "acknowledge" then @annotation.acknowledge!
      when "resolve"     then @annotation.resolve!(summary: params[:summary].presence)
      when "dismiss"     then @annotation.dismiss!(reason: params[:reason].presence)
      when "reply"
        role = ALLOWED_ROLES.include?(params[:role]) ? params[:role] : "agent"
        @annotation.add_reply!(message: params[:message], role: role)
      when "transition"
        new_status = params[:status]
        if Annotation::STATUSES.include?(new_status)
          @annotation.update!(status: new_status)
          return head :ok
        else
          return render json: { error: "invalid status" }, status: :unprocessable_entity
        end
      else
        return redirect_to annotation_path(@annotation), alert: "Unknown action."
      end

      redirect_to annotation_path(@annotation), notice: "Annotation updated."
    end

    # GET /feedback/export.csv
    def export_csv
      scope = build_export_scope
      csv_data = generate_csv(scope)
      send_data csv_data, filename: "annotations-#{Date.current}.csv", type: "text/csv"
    end

    # GET /feedback/export.json
    def export_json
      scope = build_export_scope
      json_data = scope.map(&:as_api_json).to_json
      send_data json_data, filename: "annotations-#{Date.current}.json", type: "application/json"
    end

    private

    def set_annotation
      @annotation = Annotation.find(params[:id])
    end

    def per_page
      RailsMarkup.config.per_page
    end

    def build_base_scope
      params[:page_url].present? ? Annotation.for_page(params[:page_url]) : Annotation.all
    end

    def build_export_scope
      scope = build_base_scope.recent
      scope = scope.where(status: params[:status]) if params[:status].present? && params[:status] != "all"
      scope = scope.search(params[:q]) if params[:q].present?
      scope = scope.by_author(params[:author]) if params[:author].present?
      scope
    end

    def generate_csv(scope)
      CSV.generate(headers: true) do |csv|
        csv << %w[id status intent severity content page_url author selected_text created_at updated_at]
        scope.find_each do |ann|
          csv << [ann.id, ann.status, ann.intent, ann.severity, ann.content, ann.page_url,
                  ann.author_name, ann.selected_text, ann.created_at.iso8601, ann.updated_at.iso8601]
        end
      end
    end
  end
end

# frozen_string_literal: true

module RailsMarkup
  class DashboardController < RailsMarkup.config.base_controller_class.constantize
    before_action :set_annotation, only: %i[show update]

    # GET /feedback
    def index
      scope = Annotation.recent
      scope = scope.where(status: params[:status]) if params[:status].present? && params[:status] != "all"
      scope = scope.for_page(params[:page_url]) if params[:page_url].present?

      @current_page = (params[:page] || 1).to_i
      @annotations = scope.limit(per_page).offset((@current_page - 1) * per_page)

      @total_count = Annotation.count
      @pending_count = Annotation.pending.count
      @acknowledged_count = Annotation.acknowledged.count
      @resolved_count = Annotation.resolved.count
      @dismissed_count = Annotation.dismissed.count
      @page_urls = Annotation.distinct.pluck(:page_url).sort
      @current_status = params[:status] || "all"
      @current_page_url = params[:page_url]
    end

    # GET /feedback/annotations/:id
    def show
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

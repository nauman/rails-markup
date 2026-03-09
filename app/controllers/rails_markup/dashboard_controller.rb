# frozen_string_literal: true

module RailsMarkup
  class DashboardController < ApplicationController
    before_action :authorize!

    # GET /feedback
    def index
      annotations = Annotation.recent

      if params[:status].present? && params[:status] != "all"
        annotations = annotations.where(status: params[:status])
      end

      if params[:page_url].present?
        annotations = annotations.for_page(params[:page_url])
      end

      @annotations = annotations.limit(RailsMarkup.config.per_page)
        .offset(page_offset)

      @total_count = Annotation.count
      @pending_count = Annotation.pending.count
      @acknowledged_count = Annotation.acknowledged.count
      @resolved_count = Annotation.resolved.count
      @dismissed_count = Annotation.dismissed.count
      @page_urls = Annotation.distinct.pluck(:page_url).sort
      @current_status = params[:status] || "all"
      @current_page_url = params[:page_url]
      @current_page = (params[:page] || 1).to_i
    end

    # GET /feedback/annotations/:id
    def show
      @annotation = Annotation.find(params[:id])
    end

    # PATCH /feedback/annotations/:id
    def update
      @annotation = Annotation.find(params[:id])

      case params[:action_type]
      when "acknowledge"
        @annotation.acknowledge!
      when "resolve"
        @annotation.resolve!(summary: params[:summary].presence)
      when "dismiss"
        @annotation.dismiss!(reason: params[:reason].presence)
      when "reply"
        @annotation.add_reply!(message: params[:message], role: params[:role] || "agent")
      end

      redirect_to annotation_path(@annotation), notice: "Annotation updated."
    end

    private

    def page_offset
      ((params[:page] || 1).to_i - 1) * RailsMarkup.config.per_page
    end
  end
end

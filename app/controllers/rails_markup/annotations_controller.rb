# frozen_string_literal: true

module RailsMarkup
  class AnnotationsController < ApplicationController
    skip_forgery_protection

    before_action :set_annotation, only: %i[acknowledge resolve dismiss reply]

    # POST /feedback/api/sessions
    def create_session
      render json: { id: "rm-#{SecureRandom.hex(8)}", url: params[:url] }
    end

    # POST /feedback/api/sessions/:session_id/annotations
    def create
      annotation = Annotation.new(annotation_params)
      annotation.user_id = current_user&.id if respond_to?(:current_user, true)

      if annotation.save
        render json: annotation.as_api_json, status: :created
      else
        render json: { errors: annotation.errors.full_messages }, status: :unprocessable_entity
      end
    end

    # GET /feedback/api/health
    def health
      render json: { ok: true }
    end

    # POST /feedback/api/annotations/:id/acknowledge
    def acknowledge
      @annotation.acknowledge!
      render json: @annotation.as_api_json
    end

    # POST /feedback/api/annotations/:id/resolve
    def resolve
      @annotation.resolve!(summary: params[:summary])
      render json: @annotation.as_api_json
    end

    # POST /feedback/api/annotations/:id/dismiss
    def dismiss
      @annotation.dismiss!(reason: params[:reason])
      render json: @annotation.as_api_json
    end

    # POST /feedback/api/annotations/:id/reply
    def reply
      @annotation.add_reply!(message: params[:message], role: "agent")
      render json: @annotation.as_api_json
    end

    private

    def set_annotation
      @annotation = Annotation.find(params[:id])
    end

    def annotation_params
      permitted = params.permit(:page_url, :content, :intent, :severity, :selected_text, :selectedText, target: {}, metadata: {})
      permitted[:selected_text] ||= permitted.delete(:selectedText)
      permitted[:page_url] ||= request.referer || "/"
      permitted[:target] = normalize_target(params[:target]) if params[:target].present?
      permitted[:metadata] = params[:metadata].to_unsafe_h if params[:metadata].is_a?(ActionController::Parameters)
      permitted
    end

    def normalize_target(target)
      case target
      when String then { "selector" => target }
      when ActionController::Parameters then target.to_unsafe_h
      else {}
      end
    end
  end
end

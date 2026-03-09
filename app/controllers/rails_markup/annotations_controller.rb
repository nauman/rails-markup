# frozen_string_literal: true

module RailsMarkup
  class AnnotationsController < ApplicationController
    skip_forgery_protection

    before_action :authorize!

    # POST /feedback/api/sessions
    def create_session
      session_id = "rm-#{SecureRandom.hex(8)}"
      render json: { id: session_id, url: params[:url] }
    end

    # POST /feedback/api/sessions/:session_id/annotations
    def create
      annotation = Annotation.new(annotation_params)
      annotation.page_url = params.dig(:metadata, :url) || request.referer || "/"

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
      annotation = Annotation.find(params[:id])
      annotation.acknowledge!
      render json: annotation.as_api_json
    end

    # POST /feedback/api/annotations/:id/resolve
    def resolve
      annotation = Annotation.find(params[:id])
      annotation.resolve!(summary: params[:summary])
      render json: annotation.as_api_json
    end

    # POST /feedback/api/annotations/:id/dismiss
    def dismiss
      annotation = Annotation.find(params[:id])
      annotation.dismiss!(reason: params[:reason])
      render json: annotation.as_api_json
    end

    # POST /feedback/api/annotations/:id/reply
    def reply
      annotation = Annotation.find(params[:id])
      annotation.add_reply!(message: params[:message], role: "agent")
      render json: annotation.as_api_json
    end

    private

    def annotation_params
      permitted = params.permit(:content, :intent, :severity, :selected_text, :selectedText, target: {}, metadata: {})
      permitted[:selected_text] ||= permitted.delete(:selectedText)
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

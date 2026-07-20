# frozen_string_literal: true

module RailsMarkup
  class AnnotationsController < RailsMarkup.config.base_controller_class.constantize
    protect_from_forgery with: :exception

    before_action :set_annotation, only: %i[acknowledge resolve dismiss reply]

    rescue_from ActiveRecord::RecordNotFound do
      render json: { error: "not found" }, status: :not_found
    end

    # POST /feedback/api/sessions
    def create_session
      render json: { id: "rm-#{SecureRandom.hex(8)}", url: params[:url] }
    end

    # POST /feedback/api/sessions/:session_id/annotations
    def create
      annotation = Annotation.new(annotation_params)
      assign_current_user(annotation)

      if annotation.client_uuid.present? && (existing = Annotation.find_by(client_uuid: annotation.client_uuid))
        return render_duplicate(existing, annotation)
      end

      if annotation.save
        fire_create_callback(annotation)
        render json: annotation.as_api_json, status: :created
      else
        render json: { errors: annotation.errors.full_messages }, status: :unprocessable_entity
      end
    rescue ActiveRecord::RecordNotUnique
      raise if annotation.client_uuid.blank?

      render_duplicate(Annotation.find_by!(client_uuid: annotation.client_uuid), annotation)
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
      return render json: { error: "message is required" }, status: :unprocessable_entity if params[:message].blank?

      @annotation.add_reply!(message: params[:message], role: "agent")
      render json: @annotation.as_api_json
    end

    private

    def set_annotation
      @annotation = Annotation.find(params[:id])
    end

    DEDUP_ATTRIBUTES = %w[user_id page_url content intent severity selected_text target metadata].freeze

    def assign_current_user(annotation)
      return unless respond_to?(:current_user, true) && current_user

      annotation.user_id = current_user.id
      author = RailsMarkup.config.resolve_author_name(current_user)
      annotation.metadata = (annotation.metadata || {}).merge("author" => author) if author
    end

    def render_duplicate(existing, candidate)
      if existing.attributes.slice(*DEDUP_ATTRIBUTES) == candidate.attributes.slice(*DEDUP_ATTRIBUTES)
        render json: existing.as_api_json, status: :ok
      else
        render json: { error: "client id already used for a different annotation" }, status: :conflict
      end
    end

    ALLOWED_TARGET_KEYS = %w[selector cssPath nearbyText boundingBox].freeze
    ALLOWED_METADATA_KEYS = %w[tool url localId sessionId author screenshot].freeze

    def fire_create_callback(annotation)
      callback = RailsMarkup.config.on_create_callback
      return unless callback.respond_to?(:call)

      callback.call(annotation)
    rescue => e
      Rails.logger.error("[rails-markup] on_create_callback error: #{e.message}")
    end

    def annotation_params
      permitted = params.permit(:page_url, :content, :intent, :severity, :selected_text, :selectedText, :clientId, target: {}, metadata: {})
      permitted[:selected_text] ||= permitted.delete(:selectedText)
      permitted[:client_uuid] = permitted.delete(:clientId)
      permitted[:page_url] ||= request.referer || "/"
      permitted[:target] = normalize_target(params[:target]) if params[:target].present?
      permitted[:metadata] = normalize_hash(params[:metadata], ALLOWED_METADATA_KEYS) if params[:metadata].present?
      permitted
    end

    def normalize_target(target)
      case target
      when String then { "selector" => target }
      when ActionController::Parameters
        target.permit(*ALLOWED_TARGET_KEYS, boundingBox: %i[x y top left width height]).to_h
      else {}
      end
    end

    def normalize_hash(value, allowed_keys)
      return {} unless value.is_a?(ActionController::Parameters)

      value.permit(*allowed_keys).to_h
    end
  end
end

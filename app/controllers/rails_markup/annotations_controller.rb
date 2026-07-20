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
      return render_invalid_metadata if client_supplied_author?

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

    # GET /feedback/api/annotations?page_url=/current?page=variant
    def index
      annotations = Annotation.for_page(params[:page_url]).recent
      render json: annotations.map(&:as_api_json)
    end

    # PUT /feedback/api/annotations/:client_uuid
    def upsert
      client_uuid = normalized_route_uuid
      return render_invalid_uuid unless client_uuid
      return render_invalid_metadata if client_supplied_author?

      dirty_fields = normalized_dirty_fields
      return render_invalid_dirty_fields unless dirty_fields

      attributes = browser_attributes
      return render_invalid_status if dirty_fields.include?("status") && !Annotation::STATUSES.include?(attributes["status"])

      annotation = Annotation.find_or_initialize_by(client_uuid: client_uuid)
      created = annotation.new_record?
      apply_desired_state(annotation, attributes, dirty_fields)
      annotation.save!
      fire_create_callback(annotation) if created
      render json: annotation.as_api_json
    rescue ActiveRecord::RecordInvalid => error
      render json: { errors: error.record.errors.full_messages }, status: :unprocessable_entity
    rescue ActiveRecord::RecordNotUnique
      annotation = Annotation.find_by!(client_uuid: client_uuid)
      apply_desired_state(annotation, attributes, dirty_fields)
      annotation.save!
      render json: annotation.as_api_json
    end

    # DELETE /feedback/api/annotations/:client_uuid
    def destroy
      client_uuid = normalized_route_uuid
      return render_invalid_uuid unless client_uuid

      Annotation.find_by(client_uuid: client_uuid)&.destroy!
      head :no_content
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
    ALLOWED_METADATA_KEYS = Annotation::BROWSER_METADATA_KEYS.freeze
    ALLOWED_DIRTY_FIELDS = (Annotation::BROWSER_ATTRIBUTES + %w[metadata status]).freeze
    DIRTY_FIELD_ALIASES = { "selectedText" => "selected_text" }.freeze

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
      requested_client_uuid = permitted.delete(:clientId).to_s.strip
      permitted[:client_uuid] = requested_client_uuid if Annotation.valid_client_uuid?(requested_client_uuid)
      permitted[:page_url] ||= request.referer || "/"
      permitted[:target] = normalize_target(params[:target]) if params[:target].present?
      permitted[:metadata] = normalize_hash(params[:metadata], ALLOWED_METADATA_KEYS) if params[:metadata].present?
      permitted
    end

    def browser_attributes
      permitted = params.permit(:page_url, :content, :intent, :severity, :status, :selected_text, :selectedText, target: {}, metadata: {})
      permitted[:selected_text] ||= permitted.delete(:selectedText)
      permitted[:target] = normalize_target(params[:target]) if params.key?(:target)
      permitted[:metadata] = normalize_hash(params[:metadata], ALLOWED_METADATA_KEYS) if params.key?(:metadata)
      permitted.to_h.stringify_keys
    end

    def apply_desired_state(annotation, attributes, dirty_fields)
      assign_current_user(annotation) if annotation.new_record?
      annotation.apply_browser_state(attributes, dirty_fields: dirty_fields)
    end

    def normalized_route_uuid
      uuid = params[:client_uuid].to_s.strip
      uuid if Annotation.valid_client_uuid?(uuid)
    end

    def normalized_dirty_fields
      fields = params[:dirtyFields] || []
      return unless fields.is_a?(Array)

      fields = fields.map { |field| DIRTY_FIELD_ALIASES.fetch(field.to_s, field.to_s) }
      fields if (fields - ALLOWED_DIRTY_FIELDS).empty?
    end

    def client_supplied_author?
      metadata = params[:metadata]
      metadata.respond_to?(:key?) && (metadata.key?(:author) || metadata.key?("author"))
    end

    def render_invalid_uuid
      render json: { error: "client uuid must be a canonical UUID" }, status: :unprocessable_entity
    end

    def render_invalid_metadata
      render json: { error: "author metadata is server owned" }, status: :unprocessable_entity
    end

    def render_invalid_dirty_fields
      render json: { error: "invalid dirty fields" }, status: :unprocessable_entity
    end

    def render_invalid_status
      render json: { error: "invalid status" }, status: :unprocessable_entity
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

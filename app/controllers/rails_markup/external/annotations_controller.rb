# frozen_string_literal: true

module RailsMarkup
  module External
    class AnnotationsController < ActionController::API
      before_action :authenticate_token!
      before_action :set_annotation, only: %i[show acknowledge resolve dismiss reply]

      rescue_from ActiveRecord::RecordNotFound do
        render json: { error: "not found" }, status: :not_found
      end

      # GET /external/pending
      def pending
        annotations = Annotation.pending.recent.limit(50)
        render json: { annotations: annotations.map(&:as_api_json) }
      end

      # GET /external/:id
      def show
        render json: @annotation.as_api_json
      end

      # PATCH /external/:id/acknowledge
      def acknowledge
        @annotation.acknowledge!
        render json: @annotation.as_api_json
      end

      # PATCH /external/:id/resolve
      def resolve
        @annotation.resolve!(summary: params[:summary])
        render json: @annotation.as_api_json
      end

      # PATCH /external/:id/dismiss
      def dismiss
        @annotation.dismiss!(reason: params[:reason])
        render json: @annotation.as_api_json
      end

      # PATCH /external/:id/reply
      def reply
        return render json: { error: "message is required" }, status: :unprocessable_entity if params[:message].blank?

        @annotation.add_reply!(message: params[:message], role: "agent")
        render json: @annotation.as_api_json
      end

      private

      def set_annotation
        @annotation = Annotation.find(params[:id])
      end

      def authenticate_token!
        # Development — allow all requests without token (dev server may bind to LAN IP)
        return if Rails.env.development?

        token = RailsMarkup.config.api_token
        return head(:not_found) if token.nil?

        provided = request.headers["Authorization"]&.delete_prefix("Bearer ")
        head(:unauthorized) unless ActiveSupport::SecurityUtils.secure_compare(provided.to_s, token)
      end
    end
  end
end

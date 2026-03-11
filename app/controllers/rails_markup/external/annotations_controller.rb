# frozen_string_literal: true

module RailsMarkup
  module External
    class AnnotationsController < ActionController::API
      before_action :authenticate_token!
      before_action :set_annotation, only: %i[show acknowledge resolve dismiss reply]

      # GET /feedback/external/annotations/pending
      def pending
        annotations = Annotation.pending.recent.limit(50)
        render json: { annotations: annotations.map(&:as_api_json) }
      end

      # GET /feedback/external/annotations/:id
      def show
        render json: @annotation.as_api_json
      end

      # PATCH /feedback/external/annotations/:id/acknowledge
      def acknowledge
        @annotation.acknowledge!
        render json: @annotation.as_api_json
      end

      # PATCH /feedback/external/annotations/:id/resolve
      def resolve
        @annotation.resolve!(summary: params[:summary])
        render json: @annotation.as_api_json
      end

      # PATCH /feedback/external/annotations/:id/dismiss
      def dismiss
        @annotation.dismiss!(reason: params[:reason])
        render json: @annotation.as_api_json
      end

      # PATCH /feedback/external/annotations/:id/reply
      def reply
        @annotation.add_reply!(message: params[:message], role: "agent")
        render json: @annotation.as_api_json
      end

      private

      def set_annotation
        @annotation = Annotation.find(params[:id])
      end

      def authenticate_token!
        # Development/test — always allow (no token needed locally)
        return if Rails.env.development? || Rails.env.test?

        token = RailsMarkup.config.api_token
        return head(:not_found) if token.nil?

        provided = request.headers["Authorization"]&.delete_prefix("Bearer ")
        head(:unauthorized) unless ActiveSupport::SecurityUtils.secure_compare(provided.to_s, token)
      end
    end
  end
end

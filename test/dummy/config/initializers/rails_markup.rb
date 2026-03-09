# frozen_string_literal: true

RailsMarkup.configure do |config|
  config.auth_check = ->(_controller) { true }
  config.api_token = "test-token-123"
end

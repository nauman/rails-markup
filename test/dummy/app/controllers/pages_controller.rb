# frozen_string_literal: true

# Minimal host controller so system tests can exercise the injected toolbar
# overlay on a real page (the engine's own dashboard lives under /feedback).
class PagesController < ActionController::Base
  layout "application"

  def index; end

  def other; end
end

# frozen_string_literal: true

class RailsMarkupTestAssetsController < ActionController::Base
  skip_forgery_protection

  TURBO_UMD_PATH = Rails.root.join(
    "..", "..", "node_modules", "@hotwired", "turbo", "dist", "turbo.es2017-umd.js"
  ).freeze

  def turbo
    send_file TURBO_UMD_PATH, type: "application/javascript", disposition: "inline"
  end
end

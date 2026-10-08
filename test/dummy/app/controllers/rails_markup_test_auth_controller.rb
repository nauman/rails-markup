# frozen_string_literal: true

class RailsMarkupTestAuthController < ActionController::Base
  before_action :require_rails_markup_admin

  private

  def require_rails_markup_admin
    redirect_to main_app.new_rails_markup_test_session_path unless session[:rails_markup_admin]
  end
end

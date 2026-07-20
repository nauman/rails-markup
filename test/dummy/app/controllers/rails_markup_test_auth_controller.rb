# frozen_string_literal: true

class RailsMarkupTestAuthController < ActionController::Base
  before_action :require_rails_markup_admin

  private

  def require_rails_markup_admin
    redirect_to "/rails_markup_test_session" unless session[:rails_markup_admin]
  end
end

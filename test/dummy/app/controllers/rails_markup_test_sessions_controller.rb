# frozen_string_literal: true

class RailsMarkupTestSessionsController < ActionController::Base
  protect_from_forgery with: :exception

  def new
    render inline: <<~HTML
      <form action="/rails_markup_test_session" method="post">
        <input type="hidden" name="authenticity_token" value="<%= form_authenticity_token %>">
        <button type="submit">Authenticate</button>
      </form>
    HTML
  end

  def create
    session[:rails_markup_admin] = true
    redirect_to "/feedback"
  end
end

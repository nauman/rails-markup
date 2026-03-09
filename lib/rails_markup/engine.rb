# frozen_string_literal: true

module RailsMarkup
  class Engine < ::Rails::Engine
    isolate_namespace RailsMarkup

    initializer "rails_markup.configuration" do
      RailsMarkup.configuration # ensure defaults are set
    end

    initializer "rails_markup.assets" do |app|
      if app.config.respond_to?(:assets)
        app.config.assets.precompile += %w[rails_markup/application.css rails_markup/toolbar.js]
      end
    end
  end
end

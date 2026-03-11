# frozen_string_literal: true

module RailsMarkup
  class Engine < ::Rails::Engine
    isolate_namespace RailsMarkup

    initializer "rails_markup.configuration" do
      RailsMarkup.configuration # ensure defaults are set
    end

    initializer "rails_markup.assets" do |app|
      if app.config.respond_to?(:assets)
        # toolbar.js is inlined via the toolbar partial, no separate asset needed
        app.config.assets.precompile += %w[rails_markup/toolbar.js]
      end
    end
  end
end

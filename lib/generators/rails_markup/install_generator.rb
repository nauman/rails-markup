# frozen_string_literal: true

require "rails/generators"
require "rails/generators/active_record"

module RailsMarkup
  module Generators
    class InstallGenerator < Rails::Generators::Base
      include ActiveRecord::Generators::Migration

      source_root File.expand_path("install/templates", __dir__)

      desc "Install Rails Markup: create migration, initializer, and mount engine routes."

      def copy_migration
        migration_template "create_rails_markup_annotations.rb.erb",
          "db/migrate/create_rails_markup_annotations.rb"
      end

      def create_initializer
        template "initializer.rb.erb", "config/initializers/rails_markup.rb"
      end

      def mount_engine
        route 'mount RailsMarkup::Engine, at: "/feedback"'
      end

      def show_post_install
        say ""
        say "Rails Markup installed successfully!", :green
        say ""
        say "Next steps:"
        say "  1. Run migrations:  rails db:migrate"
        say "  2. Visit dashboard: /feedback"
        say "  3. Add toolbar to your layout:"
        say '     <%= render "rails_markup/shared/toolbar" %>'
        say "  4. Configure auth in config/initializers/rails_markup.rb"
        say ""
      end

      private

      def migration_version
        "[#{ActiveRecord::Migration.current_version}]"
      end
    end
  end
end

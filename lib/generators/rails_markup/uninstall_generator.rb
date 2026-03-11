# frozen_string_literal: true

require "rails/generators"

module RailsMarkup
  module Generators
    class UninstallGenerator < Rails::Generators::Base
      desc "Uninstall Rails Markup: remove initializer, auth controller, toolbar, routes, and bin wrapper."

      class_option :remove_migration, type: :boolean, default: false,
        desc: "Also remove the migration file (dangerous — only if table was never created)"

      def remove_route_mount
        route_file = File.join(destination_root, "config/routes.rb")
        return unless File.exist?(route_file)

        gsub_file "config/routes.rb", /^\s*mount RailsMarkup::Engine.*\n/, ""
        say_status :remove, "RailsMarkup engine mount from routes", :green
      end

      def remove_initializer
        path = "config/initializers/rails_markup.rb"
        remove_file path if File.exist?(File.join(destination_root, path))
      end

      def remove_auth_controller
        path = "app/controllers/rails_markup_auth_controller.rb"
        full_path = File.join(destination_root, path)
        return unless File.exist?(full_path)

        content = File.read(full_path)
        if content.include?("RailsMarkupAuthController")
          remove_file path
        else
          say_status :skip, "#{path} doesn't match generated pattern — leaving in place", :yellow
        end
      end

      def remove_toolbar_from_layouts
        Dir.glob(File.join(destination_root, "app/views/layouts/*.html.erb")).each do |layout|
          relative = layout.sub("#{destination_root}/", "")
          content = File.read(layout)
          next unless content.include?("rails_markup/shared/toolbar")

          gsub_file relative, /^\s*<%# Rails Markup annotation toolbar %>\n/, ""
          gsub_file relative, /^\s*<% if lookup_context\.exists\?\("rails_markup\/shared\/toolbar".*%>\n\s*<%= render "rails_markup\/shared\/toolbar" %>\n\s*<% end %>\n/, ""
          say_status :remove, "toolbar from #{relative}", :green
        end
      end

      def remove_bin_wrapper
        path = "bin/markup"
        full_path = File.join(destination_root, path)
        return unless File.exist?(full_path)

        content = File.read(full_path)
        if content.include?("rails_markup") || content.include?("RailsMarkup")
          remove_file path
        else
          say_status :skip, "#{path} doesn't reference rails_markup — leaving in place", :yellow
        end
      end

      def remove_migration
        return unless options[:remove_migration]

        migration = Dir.glob(File.join(destination_root, "db/migrate/*_create_rails_markup_annotations.rb")).first
        if migration
          remove_file migration.sub("#{destination_root}/", "")
        else
          say_status :skip, "no rails_markup migration found", :yellow
        end
      end

      def show_post_uninstall
        say ""
        say "Rails Markup uninstalled.", :green
        say ""
        say "Remaining manual steps:"
        say "  1. Remove 'rails_markup' from your Gemfile and run bundle"
        unless options[:remove_migration]
          say "  2. Drop the table: rails db:migrate:down VERSION=<migration_version>"
          say "     Or: rails generate rails_markup:uninstall --remove-migration"
        end
        say "  3. Search for stale references: grep -r 'rails_markup\\|RailsMarkup' app/ config/"
        say ""
      end
    end
  end
end

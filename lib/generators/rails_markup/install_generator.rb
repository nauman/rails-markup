# frozen_string_literal: true

require "rails/generators"
require "rails/generators/active_record"

module RailsMarkup
  module Generators
    class InstallGenerator < Rails::Generators::Base
      include ActiveRecord::Generators::Migration

      source_root File.expand_path("install/templates", __dir__)

      desc "Install Rails Markup: create migration, initializer, auth controller, toolbar, and mount engine routes."

      class_option :mount_path, type: :string, default: "/admin/annotations",
        desc: "Path to mount the Rails Markup engine"
      class_option :base_controller, type: :string, default: "ApplicationController",
        desc: "Base controller class for authentication"
      class_option :layout, type: :string, default: "application",
        desc: "Layout to inject the toolbar into"

      def copy_migration
        migration_template "create_rails_markup_annotations.rb.erb",
          "db/migrate/create_rails_markup_annotations.rb"
      end

      def create_initializer
        template "initializer.rb.erb", "config/initializers/rails_markup.rb"
      end

      def create_auth_controller
        template "auth_controller.rb.erb", "app/controllers/rails_markup_auth_controller.rb"
      end

      def mount_engine
        mount_path = options[:mount_path]
        route_line = %{mount RailsMarkup::Engine, at: "#{mount_path}" if defined?(RailsMarkup::Engine)}
        route route_line
      end

      def inject_toolbar_into_layout
        layout_path = "app/views/layouts/#{options[:layout]}.html.erb"

        unless File.exist?(File.join(destination_root, layout_path))
          say_status :skip, "#{layout_path} not found — add the toolbar manually", :yellow
          return
        end

        toolbar_block = <<~ERB.indent(4)
          <%# Rails Markup annotation toolbar %>
          <% if lookup_context.exists?("rails_markup/shared/toolbar", [], true) %>
            <%= render "rails_markup/shared/toolbar" %>
          <% end %>
        ERB

        if File.read(File.join(destination_root, layout_path)).include?("rails_markup/shared/toolbar")
          say_status :skip, "toolbar already present in #{layout_path}", :yellow
          return
        end

        inject_into_file layout_path, toolbar_block, before: %r{</body>}
      end

      def inject_procfile
        procfile = File.join(destination_root, "Procfile.dev")
        return unless File.exist?(procfile)

        content = File.read(procfile)

        if content =~ /^markup:/
          unless content =~ /^markup:\s*bin\/markup\s+server/
            gsub_file "Procfile.dev", /^markup:.*$/, "markup: bin/markup server"
            say_status :update, "Procfile.dev (markup → bin/markup server)", :green
          else
            say_status :skip, "Procfile.dev already uses bin/markup server", :yellow
          end
        else
          append_to_file "Procfile.dev", "markup: bin/markup server\n"
          say_status :append, "Procfile.dev (added markup server)", :green
        end
      end

      def create_bin_wrapper
        template "bin_markup.erb", "bin/markup"
        chmod "bin/markup", 0o755
      end

      def configure_mcp
        require_relative "../../rails_markup/mcp_config"
        config = RailsMarkup::McpConfig.new(dir: destination_root)
        dev_url = detect_dev_url
        env_updates = {
          "RAILS_MARKUP_DEV_URL" => dev_url,
          "RAILS_MARKUP_MOUNT_PATH" => options[:mount_path]
        }
        config.update_env(env_updates)
        say_status :create, ".mcp.json (dev URL: #{dev_url})", :green
      end

      def show_post_install
        say ""
        say "Rails Markup installed successfully!", :green
        say ""
        say "Created:"
        say "  - db/migrate/*_create_rails_markup_annotations.rb"
        say "  - config/initializers/rails_markup.rb"
        say "  - app/controllers/rails_markup_auth_controller.rb"
        say "  - bin/markup"
        say "  - .mcp.json (MCP config for AI agents)"
        say ""
        say "Next steps:"
        say "  1. Run migrations:  rails db:migrate"
        say "  2. Visit dashboard: #{options[:mount_path]}"
        say "  3. Configure auth in config/initializers/rails_markup.rb"
        say ""
        dev_url = detect_dev_url
        unless dev_url == "http://localhost:3000"
          say "Detected dev server: #{dev_url} (from Procfile.dev)"
        end
        say ""
        say "Not using localhost:3000? Update your dev URL:", :yellow
        say "  bin/markup configure --dev-url=http://YOUR_HOST:PORT"
        say ""
        say "CLI commands:"
        say "  bin/markup fetch              # See pending annotations"
        say "  bin/markup fetch --env=production  # From production"
        say "  bin/markup configure --prod-url=URL --prod-token=TOKEN"
        say "  bin/markup status             # Show current config"
        say ""
      end

      private

      def migration_version
        "[#{ActiveRecord::Migration.current_version}]"
      end

      def detect_dev_url
        # Try to read bind address and port from Procfile.dev
        procfile = File.join(destination_root, "Procfile.dev")
        if File.exist?(procfile)
          content = File.read(procfile)
          if content =~ /-b\s+([\d.]+)\s+-p\s+(\d+)/
            return "http://#{$1}:#{$2}"
          end
          if content =~ /-p\s+(\d+)/
            return "http://localhost:#{$1}"
          end
        end

        "http://localhost:3000"
      end
    end
  end
end

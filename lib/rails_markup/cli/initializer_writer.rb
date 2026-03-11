# frozen_string_literal: true

module RailsMarkup
  class Cli
    # Reads/writes config/initializers/rails_markup.rb with upsert semantics.
    # Handles toolbar_accent, toolbar_position, toolbar_size, enable_screenshots.
    class InitializerWriter
      MANAGED_KEYS = %w[toolbar_accent toolbar_position toolbar_size enable_screenshots].freeze

      def initialize(dir: Dir.pwd)
        @path = File.join(dir, "config", "initializers", "rails_markup.rb")
      end

      def write(**options)
        content = File.exist?(@path) ? File.read(@path) : template
        options.each do |key, value|
          content = upsert_config(content, key.to_s, value)
        end
        File.write(@path, content)
      end

      private

      def upsert_config(content, key, value)
        formatted = format_value(value)
        pattern = /^(\s*)#?\s*config\.#{Regexp.escape(key)}\s*=.*$/

        if content.match?(pattern)
          content.gsub(pattern, "\\1config.#{key} = #{formatted}")
        else
          content.sub(/^(end\s*)$/, "  config.#{key} = #{formatted}\n\\1")
        end
      end

      def format_value(value)
        case value
        when true, false then value.to_s
        when Integer, Float then value.to_s
        else %("#{value}")
        end
      end

      def template
        <<~RUBY
          RailsMarkup.configure do |config|
          end
        RUBY
      end
    end
  end
end

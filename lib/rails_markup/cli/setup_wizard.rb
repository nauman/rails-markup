# frozen_string_literal: true

require "bubbletea"
require "lipgloss"
require_relative "../mcp_config"
require_relative "initializer_writer"

module RailsMarkup
  class Cli
    # Interactive TUI setup wizard using Bubbletea's Elm architecture.
    # 6-step state machine: accent → position → size → screenshots → url → confirm
    class SetupWizard
      include Bubbletea::Model

      STEPS = %i[accent position size screenshots url confirm].freeze

      STEP_CONFIG = {
        accent: {
          title: "Toolbar Accent",
          type: :select,
          options: %w[indigo amber blue emerald rose]
        },
        position: {
          title: "Toolbar Position",
          type: :select,
          options: %w[bl br tl tr],
          labels: { "bl" => "Bottom-left", "br" => "Bottom-right", "tl" => "Top-left", "tr" => "Top-right" }
        },
        size: {
          title: "Toolbar Size",
          type: :select,
          options: %w[slim compact default],
          labels: { "slim" => "Slim (32px)", "compact" => "Compact (40px)", "default" => "Default (48px)" }
        },
        screenshots: {
          title: "Enable Screenshots",
          type: :select,
          options: %w[yes no],
          labels: { "yes" => "Yes", "no" => "No" }
        },
        url: {
          title: "Production URL",
          type: :text,
          hint: "Optional — press Enter to skip"
        },
        confirm: {
          title: "Confirm Setup",
          type: :confirm
        }
      }.freeze

      HEADER_STYLE = Lipgloss::Style.new.bold(true).foreground("#FFFFFF").background("#5C4AE4").padding(0, 1)
      HINT_STYLE   = Lipgloss::Style.new.foreground("#6B7280")
      CURSOR_STYLE = Lipgloss::Style.new.bold(true).foreground("#818cf8")
      OPTION_STYLE = Lipgloss::Style.new.foreground("#E2E2E2")

      attr_reader :completed, :choices

      def initialize(dir: Dir.pwd)
        @dir = dir
        @step_index = 0
        @cursor = 0
        @choices = {}
        @text_input = ""
        @completed = false
      end

      def init
        [self, nil]
      end

      def update(message)
        case message
        when Bubbletea::KeyMessage
          handle_key(message)
        else
          [self, nil]
        end
      end

      def view
        step = current_step
        config = STEP_CONFIG[step]

        lines = []
        lines << HEADER_STYLE.render(" Rails Markup Setup — Step #{@step_index + 1}/#{STEPS.size} ")
        lines << ""
        lines << "  #{config[:title]}"
        lines << ""

        case config[:type]
        when :select
          config[:options].each_with_index do |opt, i|
            label = config.dig(:labels, opt) || opt
            if i == @cursor
              lines << "  #{CURSOR_STYLE.render("▸")} #{label}"
            else
              lines << "    #{OPTION_STYLE.render(label)}"
            end
          end
        when :text
          lines << "  #{HINT_STYLE.render(config[:hint])}"
          lines << ""
          lines << "  > #{@text_input}█"
        when :confirm
          lines << render_summary
          lines << ""
          lines << "  #{HINT_STYLE.render("Press Enter to write config, Esc to cancel")}"
        end

        lines << ""
        lines << "  #{HINT_STYLE.render("↑/↓ navigate · Enter select · Esc cancel")}" unless step == :confirm

        lines.join("\n")
      end

      private

      def current_step
        STEPS[@step_index]
      end

      def handle_key(msg)
        return [self, Bubbletea.quit] if msg.esc?

        step = current_step
        config = STEP_CONFIG[step]

        case config[:type]
        when :select then handle_select(msg, config)
        when :text   then handle_text(msg)
        when :confirm then handle_confirm(msg)
        else [self, nil]
        end
      end

      def handle_select(msg, config)
        if msg.up?
          @cursor = (@cursor - 1) % config[:options].size
        elsif msg.down?
          @cursor = (@cursor + 1) % config[:options].size
        elsif msg.enter?
          value = config[:options][@cursor]
          store_choice(current_step, value)
          advance_step
        end

        [self, nil]
      end

      def handle_text(msg)
        if msg.enter?
          store_choice(:url, @text_input.empty? ? nil : @text_input)
          advance_step
        elsif msg.backspace?
          @text_input = @text_input[0..-2] || ""
        elsif msg.runes?
          @text_input += msg.char if msg.char
        end

        [self, nil]
      end

      def handle_confirm(msg)
        if msg.enter?
          write_config
          @completed = true
          return [self, Bubbletea.quit]
        end

        [self, nil]
      end

      def store_choice(step, value)
        case step
        when :accent      then @choices[:toolbar_accent] = value
        when :position    then @choices[:toolbar_position] = value
        when :size        then @choices[:toolbar_size] = value
        when :screenshots then @choices[:enable_screenshots] = (value == "yes")
        when :url         then @choices[:url] = value
        end
      end

      def advance_step
        @step_index += 1
        @cursor = 0
        @text_input = ""
      end

      def write_config
        writer = InitializerWriter.new(dir: @dir)
        init_opts = @choices.except(:url)
        writer.write(**init_opts)

        if @choices[:url]
          config = McpConfig.new(dir: @dir)
          config.update_env("RAILS_MARKUP_PROD_URL" => @choices[:url])
        end
      end

      def render_summary
        lines = @choices.map do |key, value|
          "  #{key}: #{value.nil? ? '(skipped)' : value}"
        end
        lines.join("\n")
      end
    end
  end
end

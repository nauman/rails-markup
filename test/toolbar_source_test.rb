# frozen_string_literal: true

require "minitest/autorun"

class ToolbarSourceTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def test_toolbar_definition_is_a_singleton_across_turbo_renders
    source = File.read(File.join(ROOT, "app/assets/javascripts/rails_markup/toolbar.js"))

    assert_includes source, "if (global.RailsMarkupToolbar) return;"
  end

  def test_only_the_partial_owns_the_turbo_load_listener
    source = File.read(File.join(ROOT, "app/assets/javascripts/rails_markup/toolbar.js"))
    partial = File.read(File.join(ROOT, "app/views/rails_markup/shared/_toolbar.html.erb"))

    assert_equal 0, source.scan('document.addEventListener("turbo:load"').size
    assert_equal 1, partial.scan('document.addEventListener("turbo:load"').size
  end

  def test_turbo_reinitialization_deactivates_old_page_handlers_before_rebinding
    source = File.read(File.join(ROOT, "app/assets/javascripts/rails_markup/toolbar.js"))

    assert_includes source, "if (previousPathname && previousPathname !== window.location.pathname) this._deactivateMode();"
  end

  def test_partial_skips_toolbar_when_disabled
    partial = File.read(File.join(ROOT, "app/views/rails_markup/shared/_toolbar.html.erb"))

    assert_includes partial, "RailsMarkup.config.toolbar_enabled"
  end
end

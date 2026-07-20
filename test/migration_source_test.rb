# frozen_string_literal: true

require "test_helper"

# Guards the client_uuid migration against hardcoding the default table name,
# which silently skips the migration (and defeats create-dedup) on installs
# that set a custom config.table_name.
class MigrationSourceTest < ActiveSupport::TestCase
  MIGRATION = File.expand_path(
    "../db/migrate/20260720000000_add_client_uuid_to_rails_markup_annotations.rb", __dir__
  )

  test "client_uuid migration derives the table name from config" do
    source = File.read(MIGRATION)

    assert_match(/RailsMarkup\.config\.table_name/, source,
                 "migration must honor config.table_name")
    assert_no_match(/:rails_markup_annotations/, source,
                    "migration must not hardcode the default table name")
    assert_match(/unique: true/, source, "client_uuid index must be unique")
  end
end

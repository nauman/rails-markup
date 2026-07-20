# frozen_string_literal: true

require "minitest/autorun"

# Pure source-string checks — no Rails needed, so it runs standalone (not
# load-order coupled). Guards the client_uuid migration against hardcoding the
# default table name, which silently skips the migration (and defeats
# create-dedup) on installs that set a custom config.table_name.
class MigrationSourceTest < Minitest::Test
  MIGRATION = File.expand_path(
    "../db/migrate/20260720000000_add_client_uuid_to_rails_markup_annotations.rb", __dir__
  )
  BACKFILL_MIGRATION = File.expand_path(
    "../db/migrate/20260721000000_backfill_rails_markup_client_uuids.rb", __dir__
  )

  def test_client_uuid_migration_derives_the_table_name_from_config
    source = File.read(MIGRATION)

    assert_includes source, "RailsMarkup.config.table_name",
                    "migration must honor config.table_name"
    refute_includes source, ":rails_markup_annotations",
                    "migration must not hardcode the default table name"
    assert_includes source, "unique: true", "client_uuid index must be unique"
  end


  def test_backfill_migration_is_custom_table_and_adapter_safe
    source = File.read(BACKFILL_MIGRATION)

    assert_includes source, "RailsMarkup.config.table_name"
    refute_includes source, ":rails_markup_annotations"
    assert_includes source, "SecureRandom.uuid"
    assert_includes source, "quote_table_name"
    assert_includes source, "quote_column_name"
    assert_includes source, "change_column_null"
  end
end

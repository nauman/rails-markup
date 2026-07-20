# frozen_string_literal: true

class AddClientUuidToRailsMarkupAnnotations < ActiveRecord::Migration[7.0]
  def change
    # Honor a custom config.table_name — hardcoding the default silently skips
    # the migration (and defeats create-dedup) on installs that renamed the table.
    table = RailsMarkup.config.table_name.to_sym
    return unless table_exists?(table)

    add_column table, :client_uuid, :string, limit: 64 unless column_exists?(table, :client_uuid)
    add_index table, :client_uuid, unique: true unless index_exists?(table, :client_uuid, unique: true)
  end
end

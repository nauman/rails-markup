# frozen_string_literal: true

require "securerandom"
require "set"

class BackfillRailsMarkupClientUuids < ActiveRecord::Migration[7.0]
  UUID_PATTERN = /\A[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/i

  def up
    table = RailsMarkup.config.table_name.to_sym
    return unless table_exists?(table)

    add_column table, :client_uuid, :string, limit: 64 unless column_exists?(table, :client_uuid)
    backfill_client_uuids(table)
    change_column_null table, :client_uuid, false
    ensure_unique_index(table)
  end

  def down
    table = RailsMarkup.config.table_name.to_sym
    return unless table_exists?(table) && column_exists?(table, :client_uuid)

    change_column_null table, :client_uuid, true
  end

  private

  def backfill_client_uuids(table)
    primary_key = connection.primary_key(table)
    raise "Rails Markup annotations table must have a primary key" unless primary_key

    quoted_table = connection.quote_table_name(table)
    quoted_primary_key = connection.quote_column_name(primary_key)
    quoted_client_uuid = connection.quote_column_name(:client_uuid)
    rows = connection.select_rows(<<~SQL.squish)
      SELECT #{quoted_primary_key}, #{quoted_client_uuid}
      FROM #{quoted_table}
      ORDER BY #{quoted_primary_key}
    SQL
    used = Set.new

    rows.each do |id, current_uuid|
      if canonical_uuid?(current_uuid) && used.add?(current_uuid.downcase)
        next
      end

      replacement = next_unique_uuid(used)
      execute <<~SQL.squish
        UPDATE #{quoted_table}
        SET #{quoted_client_uuid} = #{connection.quote(replacement)}
        WHERE #{quoted_primary_key} = #{connection.quote(id)}
      SQL
    end
  end

  def canonical_uuid?(value)
    value.is_a?(String) && UUID_PATTERN.match?(value)
  end

  def next_unique_uuid(used)
    loop do
      uuid = SecureRandom.uuid
      return uuid if used.add?(uuid)
    end
  end

  def ensure_unique_index(table)
    existing = connection.indexes(table).find { |index| index.columns == ["client_uuid"] }
    remove_index table, name: existing.name if existing && !existing.unique
    add_index table, :client_uuid, unique: true unless index_exists?(table, :client_uuid, unique: true)
  end
end

# frozen_string_literal: true

require "securerandom"
require "set"

module RailsMarkup
  module ClientUuidMaintenance
    UUID_PATTERN = /\A[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/i

    module_function

    def repair!(connection: ActiveRecord::Base.connection, table_name: RailsMarkup.config.table_name)
      table = table_name.to_sym
      return 0 unless connection.table_exists?(table)

      connection.add_column(table, :client_uuid, :string, limit: 64) unless connection.column_exists?(table, :client_uuid)
      repaired = repair_rows(connection, table)
      ensure_unique_index(connection, table)
      repaired
    end

    def invalid_count(connection: ActiveRecord::Base.connection, table_name: RailsMarkup.config.table_name)
      table = table_name.to_sym
      return 0 unless connection.table_exists?(table) && connection.column_exists?(table, :client_uuid)

      quoted_table = connection.quote_table_name(table)
      quoted_client_uuid = connection.quote_column_name(:client_uuid)
      connection.select_values("SELECT #{quoted_client_uuid} FROM #{quoted_table}").count do |value|
        !canonical_uuid?(value)
      end
    end

    def verify!(connection: ActiveRecord::Base.connection, table_name: RailsMarkup.config.table_name)
      table = table_name.to_sym
      unless connection.table_exists?(table) && connection.column_exists?(table, :client_uuid)
        raise "Rails Markup client UUID storage is not installed"
      end

      invalid = invalid_count(connection:, table_name:)
      raise "Rails Markup has #{invalid} annotation(s) without canonical client UUIDs" if invalid.positive?
      unless connection.index_exists?(table, :client_uuid, unique: true)
        raise "Rails Markup client UUID unique index is missing"
      end

      true
    end

    def repair_rows(connection, table)
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
      repaired = 0

      rows.each do |id, current_uuid|
        if canonical_uuid?(current_uuid) && used.add?(current_uuid.downcase)
          next
        end

        replacement = next_unique_uuid(used)
        connection.execute <<~SQL.squish
          UPDATE #{quoted_table}
          SET #{quoted_client_uuid} = #{connection.quote(replacement)}
          WHERE #{quoted_primary_key} = #{connection.quote(id)}
        SQL
        repaired += 1
      end
      repaired
    end
    private_class_method :repair_rows

    def canonical_uuid?(value)
      value.is_a?(String) && UUID_PATTERN.match?(value)
    end
    private_class_method :canonical_uuid?

    def next_unique_uuid(used)
      loop do
        uuid = SecureRandom.uuid
        return uuid if used.add?(uuid)
      end
    end
    private_class_method :next_unique_uuid

    def ensure_unique_index(connection, table)
      existing = connection.indexes(table).find { |index| index.columns == ["client_uuid"] }
      connection.remove_index(table, name: existing.name) if existing && !existing.unique
      connection.add_index(table, :client_uuid, unique: true) unless connection.index_exists?(table, :client_uuid, unique: true)
    end
    private_class_method :ensure_unique_index
  end
end

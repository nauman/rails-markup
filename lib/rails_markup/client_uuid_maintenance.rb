# frozen_string_literal: true

require "securerandom"
require "set"
require "digest/sha1"

module RailsMarkup
  module ClientUuidMaintenance
    UUID_PATTERN = /\A[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/
    UUID_INPUT_PATTERN = /\A[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/i
    COLLISION_UUID_NAMESPACE = "102f1c26-3ad7-5b5c-871a-44c5f2392790"

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
      duplicates = casefold_duplicate_count(connection, table)
      raise "Rails Markup has #{duplicates} case-fold duplicate client UUID(s)" if duplicates.positive?
      raise "Rails Markup has #{invalid} annotation(s) without canonical client UUIDs" if invalid.positive?
      unless connection.indexes(table).any? { |index| full_unique_client_uuid_index?(index) }
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
      assignments = []

      rows.each do |id, current_uuid|
        normalized = normalize_uuid(current_uuid)
        desired = if normalized && used.add?(normalized)
          normalized
        elsif normalized
          next_collision_uuid(used, normalized, id)
        else
          next_unique_uuid(used)
        end
        assignments << [id, current_uuid, desired] unless current_uuid == desired
      end

      reserved = Set.new(rows.filter_map { |_id, value| value.to_s.downcase.presence }).merge(used)
      assignments.each do |id, _current_uuid, _desired|
        temporary = next_unique_uuid(reserved)
        update_uuid(connection, quoted_table, quoted_primary_key, quoted_client_uuid, id, temporary)
      end
      assignments.each do |id, _current_uuid, desired|
        update_uuid(connection, quoted_table, quoted_primary_key, quoted_client_uuid, id, desired)
      end
      assignments.length
    end
    private_class_method :repair_rows

    def canonical_uuid?(value)
      value.is_a?(String) && UUID_PATTERN.match?(value)
    end
    private_class_method :canonical_uuid?

    def normalize_uuid(value)
      value.downcase if value.is_a?(String) && UUID_INPUT_PATTERN.match?(value)
    end
    private_class_method :normalize_uuid

    def update_uuid(connection, table, primary_key, client_uuid, id, value)
      connection.execute <<~SQL.squish
        UPDATE #{table}
        SET #{client_uuid} = #{connection.quote(value)}
        WHERE #{primary_key} = #{connection.quote(id)}
      SQL
    end
    private_class_method :update_uuid

    def next_unique_uuid(used)
      loop do
        uuid = SecureRandom.uuid
        return uuid if used.add?(uuid)
      end
    end
    private_class_method :next_unique_uuid

    def next_collision_uuid(used, normalized, id)
      counter = 0
      loop do
        uuid = namespaced_uuid("casefold\0#{normalized}\0#{id}\0#{counter}")
        return uuid if used.add?(uuid)
        counter += 1
      end
    end
    private_class_method :next_collision_uuid

    def namespaced_uuid(name)
      namespace = [COLLISION_UUID_NAMESPACE.delete("-")].pack("H*")
      bytes = Digest::SHA1.digest(namespace + name).bytes.first(16)
      bytes[6] = (bytes[6] & 0x0f) | 0x50
      bytes[8] = (bytes[8] & 0x3f) | 0x80
      hex = bytes.pack("C*").unpack1("H*")
      "#{hex[0, 8]}-#{hex[8, 4]}-#{hex[12, 4]}-#{hex[16, 4]}-#{hex[20, 12]}"
    end
    private_class_method :namespaced_uuid

    def ensure_unique_index(connection, table)
      indexes = connection.indexes(table)
      return if indexes.any? { |index| full_unique_client_uuid_index?(index) }

      default_name = connection.index_name(table, column: [:client_uuid])
      conflict = indexes.find { |index| index.name == default_name }
      connection.remove_index(table, name: conflict.name) if conflict
      connection.add_index(table, :client_uuid, unique: true, name: default_name)
    end
    private_class_method :ensure_unique_index

    def casefold_duplicate_count(connection, table)
      quoted_table = connection.quote_table_name(table)
      quoted_client_uuid = connection.quote_column_name(:client_uuid)
      normalized = connection.select_values("SELECT #{quoted_client_uuid} FROM #{quoted_table}").filter_map do |value|
        normalize_uuid(value)
      end
      normalized.length - normalized.uniq.length
    end
    private_class_method :casefold_duplicate_count

    def full_unique_client_uuid_index?(index)
      return false unless index.unique && index.columns == ["client_uuid"]
      return false unless !index.respond_to?(:where) || index.where.nil? || index.where.to_s.strip.empty?
      return true unless index.respond_to?(:lengths)

      lengths = index.lengths
      client_length = case lengths
      when Hash then lengths["client_uuid"] || lengths[:client_uuid]
      when Array then lengths[index.columns.index("client_uuid")]
      end
      client_length.nil?
    end
    private_class_method :full_unique_client_uuid_index?
  end
end

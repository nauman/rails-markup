# frozen_string_literal: true

require_relative "engine_test_helper"
require "rails_markup/client_uuid_maintenance"
require "rake"

class ClientUuidMigrationTest < ActiveSupport::TestCase
  UUID_PATTERN = /\A[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/i
  MIGRATION = File.expand_path("../db/migrate/20260721000000_backfill_rails_markup_client_uuids.rb", __dir__)

  setup do
    @original_table_name = RailsMarkup.config.table_name
    @table_name = "rails_markup_uuid_migration_#{SecureRandom.hex(4)}"
    RailsMarkup.config.table_name = @table_name
    connection.create_table(@table_name) do |table|
      table.string :client_uuid, limit: 64
      table.string :marker
    end
    connection.add_index(@table_name, :client_uuid, unique: true)
  end

  teardown do
    connection.drop_table(@table_name, if_exists: true)
    RailsMarkup.config.table_name = @original_table_name
  end

  test "backfills blank and noncanonical identities while preserving canonical UUIDs" do
    canonical = "ad0a7a44-c458-4b05-b6dc-83e791c2a3fe"
    insert_client_uuid(nil)
    insert_client_uuid("legacy-local-id")
    insert_client_uuid(canonical)

    load MIGRATION
    migration = BackfillRailsMarkupClientUuids.new
    migration.migrate(:up)

    client_uuids = connection.select_values("SELECT client_uuid FROM #{quoted_table} ORDER BY id")
    assert_equal 3, client_uuids.uniq.length
    assert client_uuids.all? { |client_uuid| UUID_PATTERN.match?(client_uuid) }
    assert_includes client_uuids, canonical
    assert_equal true, connection.columns(@table_name).find { |column| column.name == "client_uuid" }.null
    assert connection.indexes(@table_name).any? { |index| index.unique && index.columns == ["client_uuid"] }

    migration.migrate(:up)
    assert_equal client_uuids, connection.select_values("SELECT client_uuid FROM #{quoted_table} ORDER BY id")

    insert_client_uuid(nil)
    assert_equal 1, RailsMarkup::ClientUuidMaintenance.invalid_count(connection:, table_name: @table_name)

    migration.migrate(:up)
    assert_equal 0, RailsMarkup::ClientUuidMaintenance.invalid_count(connection:, table_name: @table_name)
    repaired = connection.select_values("SELECT client_uuid FROM #{quoted_table} ORDER BY id")
    assert_equal 4, repaired.uniq.length
    assert repaired.all? { |client_uuid| UUID_PATTERN.match?(client_uuid) }
    assert RailsMarkup::ClientUuidMaintenance.verify!(connection:, table_name: @table_name)

    connection.remove_index(@table_name, :client_uuid)
    error = assert_raises(RuntimeError) do
      RailsMarkup::ClientUuidMaintenance.verify!(connection:, table_name: @table_name)
    end
    assert_match(/unique index/, error.message)
  end

  test "the host Rails application discovers repair and verify tasks" do
    Rails.application.load_tasks unless Rake::Task.task_defined?("rails_markup:client_uuids:repair")

    assert Rake::Task.task_defined?("rails_markup:client_uuids:repair")
    assert Rake::Task.task_defined?("rails_markup:client_uuids:verify")
  end

  test "repair replaces a default-name partial index and resolves case-fold duplicates" do
    connection.remove_index(@table_name, :client_uuid)
    default_name = connection.index_name(@table_name, column: [:client_uuid])
    connection.add_index(
      @table_name,
      :client_uuid,
      unique: true,
      where: "client_uuid LIKE '00000000%'",
      name: default_name
    )
    connection.add_index(@table_name, :marker, name: "index_#{@table_name}_on_marker")
    lowercase = "ad0a7a44-c458-4b05-b6dc-83e791c2a3fe"
    insert_client_uuid(lowercase.upcase)
    insert_client_uuid(lowercase)

    error = assert_raises(RuntimeError) do
      RailsMarkup::ClientUuidMaintenance.verify!(connection:, table_name: @table_name)
    end
    assert_match(/case-fold duplicate/, error.message)

    assert_equal 2, RailsMarkup::ClientUuidMaintenance.repair!(connection:, table_name: @table_name)

    repaired = connection.select_values("SELECT client_uuid FROM #{quoted_table} ORDER BY id")
    assert_equal 2, repaired.uniq.length
    assert_includes repaired, lowercase
    assert repaired.all? { |client_uuid| client_uuid == client_uuid.downcase }
    indexes = connection.indexes(@table_name)
    full = indexes.find { |index| index.columns == ["client_uuid"] && index.unique && index.where.blank? }
    assert full, "repair must establish a full unpredicated unique client_uuid index"
    assert indexes.any? { |index| index.name == "index_#{@table_name}_on_marker" }, "unrelated indexes must remain"
    assert RailsMarkup::ClientUuidMaintenance.verify!(connection:, table_name: @table_name)
  end

  test "verify rejects case-fold duplicates even with an ordinary full unique index" do
    lowercase = "5af31e48-8a93-4995-b793-09d721a1c960"
    insert_client_uuid(lowercase.upcase)
    insert_client_uuid(lowercase)

    error = assert_raises(RuntimeError) do
      RailsMarkup::ClientUuidMaintenance.verify!(connection:, table_name: @table_name)
    end
    assert_match(/case-fold duplicate/, error.message)

    assert_equal 2, RailsMarkup::ClientUuidMaintenance.repair!(connection:, table_name: @table_name)
    assert RailsMarkup::ClientUuidMaintenance.verify!(connection:, table_name: @table_name)

    comparison_table = "#{@table_name}_copy"
    connection.create_table(comparison_table) { |table| table.string :client_uuid, limit: 64 }
    connection.add_index(comparison_table, :client_uuid, unique: true)
    insert_client_uuid(lowercase.upcase, table_name: comparison_table, id: 1)
    insert_client_uuid(lowercase, table_name: comparison_table, id: 2)
    RailsMarkup::ClientUuidMaintenance.repair!(connection:, table_name: comparison_table)

    expected = connection.select_values("SELECT client_uuid FROM #{quoted_table} ORDER BY id")
    actual = connection.select_values("SELECT client_uuid FROM #{connection.quote_table_name(comparison_table)} ORDER BY id")
    assert_equal expected, actual, "case-fold collision repair must be deterministic by primary-key order"
  ensure
    connection.drop_table(comparison_table, if_exists: true) if comparison_table
  end

  test "prefix and predicate unique indexes are not full UUID constraints" do
    index = Struct.new(:unique, :columns, :where, :lengths)
    full = index.new(true, ["client_uuid"], nil, {})
    partial = index.new(true, ["client_uuid"], "client_uuid IS NOT NULL", {})
    prefixed = index.new(true, ["client_uuid"], nil, { "client_uuid" => 16 })

    assert RailsMarkup::ClientUuidMaintenance.send(:full_unique_client_uuid_index?, full)
    refute RailsMarkup::ClientUuidMaintenance.send(:full_unique_client_uuid_index?, partial)
    refute RailsMarkup::ClientUuidMaintenance.send(:full_unique_client_uuid_index?, prefixed)
  end

  private

  def connection
    ActiveRecord::Base.connection
  end

  def quoted_table
    connection.quote_table_name(@table_name)
  end

  def insert_client_uuid(client_uuid, table_name: @table_name, id: nil)
    columns = id ? "id, client_uuid" : "client_uuid"
    values = id ? "#{connection.quote(id)}, #{connection.quote(client_uuid)}" : connection.quote(client_uuid)
    connection.execute(<<~SQL.squish)
      INSERT INTO #{connection.quote_table_name(table_name)} (#{columns})
      VALUES (#{values})
    SQL
  end
end

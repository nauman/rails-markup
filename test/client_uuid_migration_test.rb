# frozen_string_literal: true

require_relative "engine_test_helper"
require "rake"

class ClientUuidMigrationTest < ActiveSupport::TestCase
  UUID_PATTERN = /\A[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/i
  MIGRATION = File.expand_path("../db/migrate/20260721000000_backfill_rails_markup_client_uuids.rb", __dir__)

  setup do
    @original_table_name = RailsMarkup.config.table_name
    @table_name = "rails_markup_uuid_migration_#{SecureRandom.hex(4)}"
    RailsMarkup.config.table_name = @table_name
    connection.create_table(@table_name) { |table| table.string :client_uuid, limit: 64 }
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

  private

  def connection
    ActiveRecord::Base.connection
  end

  def quoted_table
    connection.quote_table_name(@table_name)
  end

  def insert_client_uuid(client_uuid)
    connection.execute(<<~SQL.squish)
      INSERT INTO #{quoted_table} (client_uuid)
      VALUES (#{connection.quote(client_uuid)})
    SQL
  end
end

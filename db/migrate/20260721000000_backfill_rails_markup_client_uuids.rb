# frozen_string_literal: true

require "rails_markup/client_uuid_maintenance"

class BackfillRailsMarkupClientUuids < ActiveRecord::Migration[7.0]
  def up
    RailsMarkup::ClientUuidMaintenance.repair!(
      connection:,
      table_name: RailsMarkup.config.table_name
    )
  end

  # The expand/backfill release deliberately leaves the column nullable while
  # old application instances may still write rows. A later contract migration
  # adds NOT NULL only after repair + verification and old-instance shutdown.
  def down; end
end

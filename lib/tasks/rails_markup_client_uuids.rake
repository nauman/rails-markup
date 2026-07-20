# frozen_string_literal: true

require "rails_markup/client_uuid_maintenance"

namespace :rails_markup do
  namespace :client_uuids do
    desc "Repair blank or noncanonical Rails Markup client UUIDs (safe to repeat)"
    task repair: :environment do
      repaired = RailsMarkup::ClientUuidMaintenance.repair!
      puts "Repaired #{repaired} Rails Markup client UUID(s)."
    end

    desc "Fail unless every Rails Markup annotation has a canonical client UUID"
    task verify: :environment do
      RailsMarkup::ClientUuidMaintenance.verify!
      puts "All Rails Markup client UUIDs are canonical."
    end
  end
end

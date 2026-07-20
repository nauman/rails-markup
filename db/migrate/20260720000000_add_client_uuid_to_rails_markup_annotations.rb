# frozen_string_literal: true

class AddClientUuidToRailsMarkupAnnotations < ActiveRecord::Migration[7.0]
  def change
    return unless table_exists?(:rails_markup_annotations)

    add_column :rails_markup_annotations, :client_uuid, :string, limit: 64 unless column_exists?(:rails_markup_annotations, :client_uuid)
    add_index :rails_markup_annotations, :client_uuid, unique: true unless index_exists?(:rails_markup_annotations, :client_uuid, unique: true)
  end
end

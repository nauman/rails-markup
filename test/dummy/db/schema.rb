# frozen_string_literal: true

ActiveRecord::Schema.define do
  create_table :rails_markup_annotations, force: true do |t|
    t.bigint :user_id
    t.string :page_url, null: false
    t.text :target, default: "{}"
    t.text :content, null: false
    t.string :intent, null: false, default: "change"
    t.string :severity, null: false, default: "suggestion"
    t.string :status, null: false, default: "pending"
    t.text :selected_text
    t.text :metadata, default: "{}"
    t.text :thread, default: "[]"
    t.string :client_uuid

    t.timestamps
  end

  add_index :rails_markup_annotations, :client_uuid, unique: true
end

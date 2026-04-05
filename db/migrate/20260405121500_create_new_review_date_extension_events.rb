# frozen_string_literal: true

class CreateNewReviewDateExtensionEvents < ActiveRecord::Migration[7.1]
  def change
    create_table :new_review_date_extension_events do |t|
      t.references :new_task, null: false, foreign_key: true
      t.references :new_action_node, null: true, foreign_key: { on_delete: :nullify }
      t.string :stable_node_id
      t.date :previous_review_date, null: false
      t.date :new_review_date, null: false
      t.string :reason, null: false, limit: 32
      t.text :explanation
      t.references :recorded_by, null: false, foreign_key: { to_table: :users }

      t.timestamps
    end

    add_index :new_review_date_extension_events,
              %i[new_task_id created_at],
              name: "index_nrdee_on_new_task_id_and_created_at"
    add_index :new_review_date_extension_events,
              :reason,
              name: "index_nrdee_on_reason"
    add_index :new_review_date_extension_events,
              :stable_node_id,
              name: "index_nrdee_on_stable_node_id"
    add_index :new_review_date_extension_events,
              %i[new_action_node_id created_at],
              name: "index_nrdee_on_new_action_node_id_and_created_at"
    add_index :new_review_date_extension_events,
              %i[new_task_id reason],
              name: "index_nrdee_on_new_task_id_and_reason"
  end
end

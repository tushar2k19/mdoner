# frozen_string_literal: true

class CreateNewTaskTags < ActiveRecord::Migration[7.1]
  def change
    create_table :new_task_tags do |t|
      t.references :new_task, null: false, foreign_key: true
      t.references :tag, null: false, foreign_key: true
      t.references :created_by, foreign_key: { to_table: :users }

      t.timestamps
    end

    add_index :new_task_tags, [:new_task_id, :tag_id], unique: true, name: "index_new_task_tags_on_new_task_id_and_tag_id"
  end
end

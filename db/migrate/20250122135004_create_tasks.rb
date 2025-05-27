class CreateTasks < ActiveRecord::Migration[7.0]
  def change
    create_table :tasks do |t|
      t.string :sector_division, null: false
      t.text :description, null: false
      t.text :action_to_be_taken, null: false  # Will store TinyMCE HTML content
      t.datetime :original_date, null: false
      t.string :responsibility, null: false
      t.datetime :review_date, null: false
      t.datetime :completed_at
      t.integer :status, default: 0
      t.references :editor, foreign_key: { to_table: :users }
      t.references :reviewer, foreign_key: { to_table: :users }, null: true
      t.references :final_reviewer, foreign_key: { to_table: :users }, null: true

      t.timestamps
    end
  end
end

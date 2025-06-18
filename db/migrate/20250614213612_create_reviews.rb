class CreateReviews < ActiveRecord::Migration[7.0]
  def change
    create_table :reviews do |t|
      t.references :task_version, null: false, foreign_key: true  # Version being reviewed
      t.references :base_version, null: false, foreign_key: { to_table: :task_versions }  # Approved version for comparison
      t.references :reviewer, foreign_key: { to_table: :users }  # User responsible for review
      t.string :status, null: false, default: 'pending'  # pending/approved/changes_requested
      t.text :summary  # Review summary/notes

      t.timestamps
    end
  end
end

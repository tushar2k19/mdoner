class CreateCommentTrails < ActiveRecord::Migration[7.0]
  def change
    create_table :comment_trails do |t|
      t.references :review, null: false, foreign_key: true  # Links to the review instance
      t.timestamps
    end

    # Connect comments to trails instead of directly to tasks
    add_reference :comments, :comment_trail, foreign_key: true
    remove_reference :comments, :task  # Remove old task association
  end
end

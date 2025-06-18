class CreateCommentTrails < ActiveRecord::Migration[7.0]
  def change
    create_table :comment_trails do |t|
      t.references :review, null: false, foreign_key: true  # Links to the review instance
      t.timestamps
    end

    # Note: Comments table will already have comment_trail reference when created
  end
end

class AddReviewDateToComments < ActiveRecord::Migration[7.0]
  def up
    # First add the column as nullable
    add_column :comments, :review_date, :datetime, null: true

    # Update existing records with a default review date (current timestamp)
    Comment.unscoped.in_batches do |batch|
      batch.update_all(review_date: Time.current)
    end

    # Now make it non-nullable
    change_column_null :comments, :review_date, false
  end

  def down
    remove_column :comments, :review_date
  end
end

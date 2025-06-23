class AllowNullBaseVersionInReviews < ActiveRecord::Migration[7.0]
  def change
    change_column_null :reviews, :base_version_id, true
  end
end

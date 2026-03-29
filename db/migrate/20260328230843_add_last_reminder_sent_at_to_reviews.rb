class AddLastReminderSentAtToReviews < ActiveRecord::Migration[7.1]
  def change
    add_column :reviews, :last_reminder_sent_at, :datetime
  end
end

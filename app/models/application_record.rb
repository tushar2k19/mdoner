class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class

  # Optional table: environments without the review_date_extension_events migration
  # must not 500 when destroying tasks/versions/nodes.
  def self.review_date_extension_event_model
    "ReviewDateExtensionEvent".safe_constantize
  end

  def self.review_date_extension_events_table_exists?
    model = review_date_extension_event_model
    return false unless model.is_a?(Class)

    connection.data_source_exists?(model.table_name)
  rescue ActiveRecord::NoDatabaseError, ActiveRecord::ConnectionNotEstablished
    false
  end

  def self.delete_review_date_extension_events_where(**conditions)
    return unless review_date_extension_events_table_exists?

    model = review_date_extension_event_model
    model.unscoped.where(conditions).delete_all
  rescue ActiveRecord::StatementInvalid => e
    Rails.logger.warn("[ReviewDateExtensionEvent] delete_where skipped: #{e.message}")
  end
end

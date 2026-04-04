# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.1].define(version: 2026_04_04_190000) do
  create_table "action_nodes", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "task_version_id", null: false
    t.bigint "parent_id"
    t.text "content", size: :medium, null: false
    t.datetime "review_date"
    t.integer "level", default: 1
    t.string "list_style", default: "decimal"
    t.boolean "completed", default: false
    t.integer "position", null: false
    t.string "node_type", null: false
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "reviewer_id"
    t.string "stable_node_id"
    t.index ["deleted_at"], name: "index_action_nodes_on_deleted_at"
    t.index ["parent_id"], name: "index_action_nodes_on_parent_id"
    t.index ["reviewer_id"], name: "index_action_nodes_on_reviewer_id"
    t.index ["stable_node_id"], name: "index_action_nodes_on_stable_node_id"
    t.index ["task_version_id"], name: "index_action_nodes_on_task_version_id"
  end

  create_table "comment_trails", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "review_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "deleted_at"
    t.index ["deleted_at"], name: "index_comment_trails_on_deleted_at"
    t.index ["review_id"], name: "index_comment_trails_on_review_id"
  end

  create_table "comments", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.text "content", null: false
    t.datetime "review_date", null: false
    t.bigint "user_id", null: false
    t.bigint "comment_trail_id", null: false
    t.bigint "action_node_id"
    t.boolean "resolved", default: false
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["action_node_id"], name: "index_comments_on_action_node_id"
    t.index ["comment_trail_id"], name: "index_comments_on_comment_trail_id"
    t.index ["deleted_at"], name: "index_comments_on_deleted_at"
    t.index ["user_id"], name: "index_comments_on_user_id"
  end

  create_table "new_action_nodes", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "new_task_id", null: false
    t.bigint "parent_id"
    t.text "content", size: :long, null: false
    t.datetime "review_date"
    t.integer "level", default: 1
    t.string "list_style", default: "decimal", null: false
    t.boolean "completed", default: false, null: false
    t.integer "position", null: false
    t.string "node_type", null: false
    t.bigint "reviewer_id"
    t.string "stable_node_id"
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["deleted_at"], name: "index_new_action_nodes_on_deleted_at"
    t.index ["new_task_id", "parent_id", "position"], name: "index_new_action_nodes_on_task_parent_position"
    t.index ["new_task_id"], name: "index_new_action_nodes_on_new_task_id"
    t.index ["parent_id"], name: "index_new_action_nodes_on_parent_id"
    t.index ["reviewer_id"], name: "index_new_action_nodes_on_reviewer_id"
    t.index ["stable_node_id"], name: "index_new_action_nodes_on_stable_node_id"
  end

  create_table "new_dashboard_assignments", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "new_dashboard_version_id", null: false
    t.bigint "new_dashboard_snapshot_action_node_id", null: false
    t.bigint "user_id", null: false
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["deleted_at"], name: "index_new_dashboard_assignments_on_deleted_at"
    t.index ["new_dashboard_snapshot_action_node_id"], name: "idx_on_new_dashboard_snapshot_action_node_id_d314c79f46"
    t.index ["new_dashboard_version_id", "new_dashboard_snapshot_action_node_id", "user_id"], name: "index_new_da_on_version_node_user"
    t.index ["new_dashboard_version_id"], name: "index_new_dashboard_assignments_on_new_dashboard_version_id"
    t.index ["user_id"], name: "index_new_dashboard_assignments_on_user_id"
  end

  create_table "new_dashboard_draft_settings", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "singleton_key", default: "global", null: false
    t.date "target_meeting_date"
    t.bigint "updated_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["singleton_key"], name: "index_new_dashboard_draft_settings_on_singleton_key", unique: true
    t.index ["updated_by_id"], name: "index_new_dashboard_draft_settings_on_updated_by_id"
  end

  create_table "new_dashboard_node_comments", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "new_dashboard_version_id", null: false
    t.bigint "new_dashboard_snapshot_action_node_id", null: false
    t.bigint "user_id", null: false
    t.text "body", null: false
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["deleted_at"], name: "index_new_dashboard_node_comments_on_deleted_at"
    t.index ["new_dashboard_snapshot_action_node_id"], name: "idx_on_new_dashboard_snapshot_action_node_id_245e81ab7d"
    t.index ["new_dashboard_version_id"], name: "index_new_dashboard_node_comments_on_new_dashboard_version_id"
    t.index ["user_id"], name: "index_new_dashboard_node_comments_on_user_id"
  end

  create_table "new_dashboard_snapshot_action_nodes", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "new_dashboard_version_id", null: false
    t.bigint "new_dashboard_snapshot_task_id", null: false
    t.bigint "parent_id"
    t.bigint "source_new_action_node_id"
    t.text "content", size: :long, null: false
    t.datetime "review_date"
    t.integer "level", default: 1
    t.string "list_style", default: "decimal", null: false
    t.boolean "completed", default: false, null: false
    t.integer "position", null: false
    t.string "node_type", null: false
    t.bigint "reviewer_id"
    t.string "stable_node_id"
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["deleted_at"], name: "index_new_dashboard_snapshot_action_nodes_on_deleted_at"
    t.index ["new_dashboard_snapshot_task_id", "parent_id", "position"], name: "index_new_dsan_on_snapshot_task_parent_position"
    t.index ["new_dashboard_snapshot_task_id"], name: "idx_on_new_dashboard_snapshot_task_id_4b62714600"
    t.index ["new_dashboard_version_id"], name: "idx_on_new_dashboard_version_id_89aa156094"
    t.index ["parent_id"], name: "index_new_dashboard_snapshot_action_nodes_on_parent_id"
    t.index ["reviewer_id"], name: "fk_rails_0e03a5eb79"
    t.index ["source_new_action_node_id"], name: "idx_on_source_new_action_node_id_74134215d1"
    t.index ["stable_node_id"], name: "index_new_dashboard_snapshot_action_nodes_on_stable_node_id"
  end

  create_table "new_dashboard_snapshot_tasks", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "new_dashboard_version_id", null: false
    t.bigint "source_new_task_id"
    t.text "sector_division", size: :medium, null: false
    t.text "description", size: :medium, null: false
    t.datetime "original_date", null: false
    t.datetime "review_date", null: false
    t.text "responsibility", size: :medium, null: false
    t.datetime "completed_at"
    t.integer "status", default: 0, null: false
    t.bigint "editor_id"
    t.bigint "reviewer_id"
    t.integer "display_position", default: 0, null: false
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.json "published_tag_ids"
    t.index ["deleted_at"], name: "index_new_dashboard_snapshot_tasks_on_deleted_at"
    t.index ["editor_id"], name: "fk_rails_8707bd93fa"
    t.index ["new_dashboard_version_id", "display_position"], name: "index_new_dst_on_version_and_display_position"
    t.index ["new_dashboard_version_id"], name: "index_new_dashboard_snapshot_tasks_on_new_dashboard_version_id"
    t.index ["reviewer_id"], name: "fk_rails_d6e57de781"
    t.index ["source_new_task_id"], name: "index_new_dashboard_snapshot_tasks_on_source_new_task_id"
  end

  create_table "new_dashboard_versions", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.date "target_meeting_date", null: false
    t.datetime "published_at", null: false
    t.bigint "published_by_id", null: false
    t.string "note"
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["deleted_at"], name: "index_new_dashboard_versions_on_deleted_at"
    t.index ["published_by_id"], name: "index_new_dashboard_versions_on_published_by_id"
    t.index ["target_meeting_date", "published_at"], name: "index_new_dv_on_meeting_date_and_published_at"
  end

  create_table "new_meeting_schedule_events", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "event_type", null: false
    t.date "from_meeting_date"
    t.date "to_meeting_date"
    t.bigint "new_dashboard_version_id"
    t.bigint "new_meeting_schedule_id"
    t.bigint "actor_id", null: false
    t.json "payload"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["actor_id"], name: "index_new_meeting_schedule_events_on_actor_id"
    t.index ["created_at"], name: "index_new_meeting_schedule_events_on_created_at"
    t.index ["event_type"], name: "index_new_meeting_schedule_events_on_event_type"
    t.index ["new_dashboard_version_id"], name: "index_new_meeting_schedule_events_on_new_dashboard_version_id"
    t.index ["new_meeting_schedule_id"], name: "index_new_meeting_schedule_events_on_new_meeting_schedule_id"
  end

  create_table "new_meeting_schedules", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.date "meeting_date", null: false
    t.bigint "current_new_dashboard_version_id", null: false
    t.bigint "set_by_user_id", null: false
    t.datetime "set_at", null: false
    t.text "reason"
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["current_new_dashboard_version_id"], name: "idx_on_current_new_dashboard_version_id_7e063375c8"
    t.index ["deleted_at"], name: "index_new_meeting_schedules_on_deleted_at"
    t.index ["meeting_date"], name: "index_new_meeting_schedules_on_meeting_date"
    t.index ["set_by_user_id"], name: "index_new_meeting_schedules_on_set_by_user_id"
  end

  create_table "new_task_tags", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "new_task_id", null: false
    t.bigint "tag_id", null: false
    t.bigint "created_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_by_id"], name: "index_new_task_tags_on_created_by_id"
    t.index ["new_task_id", "tag_id"], name: "index_new_task_tags_on_new_task_id_and_tag_id", unique: true
    t.index ["new_task_id"], name: "index_new_task_tags_on_new_task_id"
    t.index ["tag_id"], name: "index_new_task_tags_on_tag_id"
  end

  create_table "new_tasks", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.text "sector_division", size: :medium, null: false
    t.text "description", size: :medium, null: false
    t.datetime "original_date", null: false
    t.datetime "review_date", null: false
    t.text "responsibility", size: :medium, null: false
    t.datetime "completed_at"
    t.integer "status", default: 0, null: false
    t.bigint "editor_id"
    t.bigint "reviewer_id"
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["deleted_at"], name: "index_new_tasks_on_deleted_at"
    t.index ["editor_id"], name: "index_new_tasks_on_editor_id"
    t.index ["reviewer_id"], name: "index_new_tasks_on_reviewer_id"
    t.index ["status"], name: "index_new_tasks_on_status"
  end

  create_table "notifications", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "recipient_id", null: false
    t.bigint "task_id", null: false
    t.bigint "review_id"
    t.string "message", null: false
    t.boolean "read", default: false
    t.string "notification_type"
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["deleted_at"], name: "index_notifications_on_deleted_at"
    t.index ["recipient_id"], name: "index_notifications_on_recipient_id"
    t.index ["review_id"], name: "index_notifications_on_review_id"
    t.index ["task_id"], name: "index_notifications_on_task_id"
  end

  create_table "review_date_extension_events", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "task_id", null: false
    t.bigint "task_version_id", null: false
    t.bigint "action_node_id"
    t.string "stable_node_id"
    t.date "previous_review_date", null: false
    t.date "new_review_date", null: false
    t.string "reason", limit: 32, null: false
    t.text "explanation"
    t.bigint "recorded_by_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["action_node_id", "created_at"], name: "index_rdee_on_action_node_id_and_created_at"
    t.index ["action_node_id"], name: "index_review_date_extension_events_on_action_node_id"
    t.index ["reason"], name: "index_rdee_on_reason"
    t.index ["recorded_by_id"], name: "index_review_date_extension_events_on_recorded_by_id"
    t.index ["stable_node_id"], name: "index_rdee_on_stable_node_id"
    t.index ["task_id", "created_at"], name: "index_rdee_on_task_id_and_created_at"
    t.index ["task_id", "reason"], name: "index_rdee_on_task_id_and_reason"
    t.index ["task_id"], name: "index_review_date_extension_events_on_task_id"
    t.index ["task_version_id"], name: "index_review_date_extension_events_on_task_version_id"
  end

  create_table "reviews", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "task_version_id", null: false
    t.bigint "base_version_id"
    t.bigint "reviewer_id"
    t.string "status", default: "pending", null: false
    t.text "summary"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "deleted_at"
    t.text "assigned_node_ids", comment: "JSON array of ActionNode IDs assigned to this review"
    t.string "reviewer_type", default: "task_level", comment: "Type of review: 'task_level' or 'node_level'"
    t.boolean "is_aggregate_review", default: false, comment: "True for task-level reviews that oversee multiple nodes"
    t.datetime "last_reminder_sent_at"
    t.index ["base_version_id"], name: "index_reviews_on_base_version_id"
    t.index ["deleted_at"], name: "index_reviews_on_deleted_at"
    t.index ["is_aggregate_review"], name: "index_reviews_on_is_aggregate_review"
    t.index ["reviewer_id"], name: "index_reviews_on_reviewer_id"
    t.index ["reviewer_type"], name: "index_reviews_on_reviewer_type"
    t.index ["task_version_id"], name: "index_reviews_on_task_version_id"
  end

  create_table "tags", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_tags_on_name", unique: true
  end

  create_table "task_tags", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "task_id", null: false
    t.bigint "tag_id", null: false
    t.bigint "created_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_by_id"], name: "index_task_tags_on_created_by_id"
    t.index ["tag_id"], name: "index_task_tags_on_tag_id"
    t.index ["task_id", "tag_id"], name: "index_task_tags_on_task_id_and_tag_id", unique: true
    t.index ["task_id"], name: "index_task_tags_on_task_id"
  end

  create_table "task_versions", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "task_id", null: false
    t.bigint "editor_id"
    t.bigint "base_version_id"
    t.integer "version_number", null: false
    t.string "status", default: "draft", null: false
    t.text "change_description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "deleted_at"
    t.index ["base_version_id"], name: "index_task_versions_on_base_version_id"
    t.index ["deleted_at"], name: "index_task_versions_on_deleted_at"
    t.index ["editor_id"], name: "index_task_versions_on_editor_id"
    t.index ["task_id"], name: "index_task_versions_on_task_id"
  end

  create_table "tasks", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.text "sector_division", size: :medium, null: false
    t.text "description", size: :medium, null: false
    t.datetime "original_date", null: false
    t.text "responsibility", size: :medium, null: false
    t.datetime "review_date", null: false
    t.datetime "completed_at"
    t.integer "status", default: 0
    t.bigint "editor_id"
    t.bigint "reviewer_id"
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "current_version_id"
    t.index ["current_version_id"], name: "index_tasks_on_current_version_id"
    t.index ["deleted_at"], name: "index_tasks_on_deleted_at"
    t.index ["editor_id"], name: "index_tasks_on_editor_id"
    t.index ["reviewer_id"], name: "index_tasks_on_reviewer_id"
  end

  create_table "users", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "first_name", null: false
    t.string "last_name"
    t.string "email", null: false
    t.string "password_digest", null: false
    t.integer "role", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  add_foreign_key "action_nodes", "action_nodes", column: "parent_id"
  add_foreign_key "action_nodes", "task_versions"
  add_foreign_key "action_nodes", "users", column: "reviewer_id"
  add_foreign_key "comment_trails", "reviews"
  add_foreign_key "comments", "action_nodes", on_delete: :nullify
  add_foreign_key "comments", "comment_trails"
  add_foreign_key "comments", "users"
  add_foreign_key "new_action_nodes", "new_action_nodes", column: "parent_id"
  add_foreign_key "new_action_nodes", "new_tasks"
  add_foreign_key "new_action_nodes", "users", column: "reviewer_id"
  add_foreign_key "new_dashboard_assignments", "new_dashboard_snapshot_action_nodes"
  add_foreign_key "new_dashboard_assignments", "new_dashboard_versions"
  add_foreign_key "new_dashboard_assignments", "users"
  add_foreign_key "new_dashboard_draft_settings", "users", column: "updated_by_id"
  add_foreign_key "new_dashboard_node_comments", "new_dashboard_snapshot_action_nodes"
  add_foreign_key "new_dashboard_node_comments", "new_dashboard_versions"
  add_foreign_key "new_dashboard_node_comments", "users"
  add_foreign_key "new_dashboard_snapshot_action_nodes", "new_action_nodes", column: "source_new_action_node_id", on_delete: :nullify
  add_foreign_key "new_dashboard_snapshot_action_nodes", "new_dashboard_snapshot_action_nodes", column: "parent_id"
  add_foreign_key "new_dashboard_snapshot_action_nodes", "new_dashboard_snapshot_tasks"
  add_foreign_key "new_dashboard_snapshot_action_nodes", "new_dashboard_versions"
  add_foreign_key "new_dashboard_snapshot_action_nodes", "users", column: "reviewer_id"
  add_foreign_key "new_dashboard_snapshot_tasks", "new_dashboard_versions"
  add_foreign_key "new_dashboard_snapshot_tasks", "new_tasks", column: "source_new_task_id", on_delete: :nullify
  add_foreign_key "new_dashboard_snapshot_tasks", "users", column: "editor_id"
  add_foreign_key "new_dashboard_snapshot_tasks", "users", column: "reviewer_id"
  add_foreign_key "new_dashboard_versions", "users", column: "published_by_id"
  add_foreign_key "new_meeting_schedule_events", "new_dashboard_versions"
  add_foreign_key "new_meeting_schedule_events", "new_meeting_schedules"
  add_foreign_key "new_meeting_schedule_events", "users", column: "actor_id"
  add_foreign_key "new_meeting_schedules", "new_dashboard_versions", column: "current_new_dashboard_version_id"
  add_foreign_key "new_meeting_schedules", "users", column: "set_by_user_id"
  add_foreign_key "new_task_tags", "new_tasks"
  add_foreign_key "new_task_tags", "tags"
  add_foreign_key "new_task_tags", "users", column: "created_by_id"
  add_foreign_key "new_tasks", "users", column: "editor_id"
  add_foreign_key "new_tasks", "users", column: "reviewer_id"
  add_foreign_key "notifications", "reviews"
  add_foreign_key "notifications", "tasks"
  add_foreign_key "notifications", "users", column: "recipient_id"
  add_foreign_key "review_date_extension_events", "action_nodes", on_delete: :nullify
  add_foreign_key "review_date_extension_events", "task_versions"
  add_foreign_key "review_date_extension_events", "tasks"
  add_foreign_key "review_date_extension_events", "users", column: "recorded_by_id"
  add_foreign_key "reviews", "task_versions"
  add_foreign_key "reviews", "task_versions", column: "base_version_id"
  add_foreign_key "reviews", "users", column: "reviewer_id"
  add_foreign_key "task_tags", "tags"
  add_foreign_key "task_tags", "tasks"
  add_foreign_key "task_tags", "users", column: "created_by_id"
  add_foreign_key "task_versions", "task_versions", column: "base_version_id"
  add_foreign_key "task_versions", "tasks"
  add_foreign_key "task_versions", "users", column: "editor_id"
  add_foreign_key "tasks", "task_versions", column: "current_version_id"
  add_foreign_key "tasks", "users", column: "editor_id"
  add_foreign_key "tasks", "users", column: "reviewer_id"
end

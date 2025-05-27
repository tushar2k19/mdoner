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

ActiveRecord::Schema[7.1].define(version: 2025_02_04_014824) do
  create_table "comments", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "task_id", null: false
    t.bigint "user_id", null: false
    t.text "content", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "review_date", null: false
    t.index ["task_id"], name: "index_comments_on_task_id"
    t.index ["user_id"], name: "index_comments_on_user_id"
  end

  create_table "notifications", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "recipient_id", null: false
    t.bigint "task_id", null: false
    t.string "message", null: false
    t.boolean "read", default: false
    t.string "notification_type"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "comment_id"
    t.index ["comment_id"], name: "index_notifications_on_comment_id"
    t.index ["recipient_id"], name: "index_notifications_on_recipient_id"
    t.index ["task_id"], name: "index_notifications_on_task_id"
  end

  create_table "tasks", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "sector_division", null: false
    t.text "description", null: false
    t.text "action_to_be_taken", null: false
    t.datetime "original_date", null: false
    t.string "responsibility", null: false
    t.datetime "review_date", null: false
    t.datetime "completed_at"
    t.integer "status", default: 0
    t.bigint "editor_id"
    t.bigint "reviewer_id"
    t.bigint "final_reviewer_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["editor_id"], name: "index_tasks_on_editor_id"
    t.index ["final_reviewer_id"], name: "index_tasks_on_final_reviewer_id"
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

  add_foreign_key "comments", "tasks"
  add_foreign_key "comments", "users"
  add_foreign_key "notifications", "tasks"
  add_foreign_key "notifications", "users", column: "recipient_id"
  add_foreign_key "tasks", "users", column: "editor_id"
  add_foreign_key "tasks", "users", column: "final_reviewer_id"
  add_foreign_key "tasks", "users", column: "reviewer_id"
end

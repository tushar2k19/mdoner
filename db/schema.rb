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

ActiveRecord::Schema[7.1].define(version: 2025_01_16_212644) do
  create_table "blocks", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "name", null: false
    t.bigint "district_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["district_id", "name"], name: "index_blocks_on_district_id_and_name", unique: true
    t.index ["district_id"], name: "index_blocks_on_district_id"
  end

  create_table "districts", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "name", null: false
    t.bigint "state_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["state_id", "name"], name: "index_districts_on_state_id_and_name", unique: true
    t.index ["state_id"], name: "index_districts_on_state_id"
  end

  create_table "farmer_images", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "image_url", null: false
    t.bigint "farmer_id", null: false
    t.bigint "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["farmer_id"], name: "index_farmer_images_on_farmer_id"
    t.index ["user_id"], name: "index_farmer_images_on_user_id"
  end

  create_table "farmers", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "first_name", null: false
    t.string "last_name"
    t.string "phone_number", null: false
    t.string "relation", null: false
    t.string "guardian_name", null: false
    t.integer "gender", null: false
    t.date "date_of_birth", null: false
    t.decimal "average_land", precision: 10, scale: 2, null: false
    t.decimal "income", precision: 10, scale: 2, null: false
    t.boolean "kit_distributed", default: false
    t.string "crop_type", null: false
    t.json "selected_crops"
    t.bigint "location_id", null: false
    t.bigint "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["first_name", "last_name"], name: "index_farmers_on_first_name_and_last_name"
    t.index ["guardian_name"], name: "index_farmers_on_guardian_name"
    t.index ["location_id"], name: "index_farmers_on_location_id"
    t.index ["phone_number"], name: "index_farmers_on_phone_number"
    t.index ["user_id"], name: "index_farmers_on_user_id"
  end

  create_table "locations", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "state_id", null: false
    t.bigint "district_id", null: false
    t.bigint "block_id", null: false
    t.bigint "village_id", null: false
    t.bigint "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["block_id"], name: "index_locations_on_block_id"
    t.index ["district_id"], name: "index_locations_on_district_id"
    t.index ["state_id", "district_id", "block_id", "village_id", "user_id"], name: "index_locations_on_state_district_block_village_user", unique: true
    t.index ["state_id"], name: "index_locations_on_state_id"
    t.index ["user_id"], name: "index_locations_on_user_id"
    t.index ["village_id"], name: "index_locations_on_village_id"
  end

  create_table "states", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_states_on_name", unique: true
  end

  create_table "users", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "first_name", null: false
    t.string "last_name", null: false
    t.string "email", null: false
    t.string "phone", null: false
    t.string "password_digest", null: false
    t.integer "role", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  create_table "villages", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "name", null: false
    t.bigint "block_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["block_id", "name"], name: "index_villages_on_block_id_and_name", unique: true
    t.index ["block_id"], name: "index_villages_on_block_id"
  end

  add_foreign_key "blocks", "districts"
  add_foreign_key "districts", "states"
  add_foreign_key "farmer_images", "farmers"
  add_foreign_key "farmer_images", "users"
  add_foreign_key "farmers", "locations"
  add_foreign_key "farmers", "users"
  add_foreign_key "locations", "blocks"
  add_foreign_key "locations", "districts"
  add_foreign_key "locations", "states"
  add_foreign_key "locations", "users"
  add_foreign_key "locations", "villages"
  add_foreign_key "villages", "blocks"
end

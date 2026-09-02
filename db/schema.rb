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

ActiveRecord::Schema[8.1].define(version: 2026_09_02_073358) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "action_text_rich_texts", force: :cascade do |t|
    t.text "body"
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.datetime "updated_at", null: false
    t.index ["record_type", "record_id", "name"], name: "index_action_text_rich_texts_uniqueness", unique: true
  end

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "applications", force: :cascade do |t|
    t.datetime "applied_at"
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.string "status", default: "wishlist", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["job_id"], name: "index_applications_on_job_id"
    t.index ["user_id", "job_id"], name: "index_applications_on_user_id_and_job_id", unique: true
    t.index ["user_id"], name: "index_applications_on_user_id"
  end

  create_table "companies", force: :cascade do |t|
    t.string "address"
    t.string "city"
    t.datetime "created_at", null: false
    t.string "domain"
    t.string "industry_code"
    t.boolean "is_cold_outreach", default: false
    t.string "name", null: false
    t.string "primary_email"
    t.datetime "updated_at", null: false
    t.string "website"
    t.index ["name"], name: "index_companies_on_name", unique: true
  end

  create_table "cover_letter_templates", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id", "name"], name: "index_cover_letter_templates_on_user_id_and_name", unique: true
    t.index ["user_id"], name: "index_cover_letter_templates_on_user_id"
  end

  create_table "jobs", force: :cascade do |t|
    t.bigint "company_id", null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.date "expires_at"
    t.string "external_id"
    t.string "hr_email"
    t.string "location"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.string "url", null: false
    t.index ["company_id"], name: "index_jobs_on_company_id"
    t.index ["external_id"], name: "index_jobs_on_external_id", unique: true
    t.index ["url"], name: "index_jobs_on_url", unique: true
  end

  create_table "scraper_configs", force: :cascade do |t|
    t.boolean "active", default: true
    t.string "card_selector"
    t.string "company_selector"
    t.datetime "created_at", null: false
    t.string "date_selector"
    t.string "link_selector"
    t.string "location_selector"
    t.string "next_page_selector"
    t.string "site_name"
    t.string "title_selector"
    t.datetime "updated_at", null: false
    t.string "url"
  end

  create_table "user_preferences", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "keywords"
    t.string "location"
    t.boolean "receive_daily_alerts", default: true
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_user_preferences_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "access_token"
    t.datetime "created_at", null: false
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "provider"
    t.string "refresh_token"
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.datetime "token_expires_at"
    t.string "uid"
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["provider", "uid"], name: "index_users_on_provider_and_uid", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "applications", "jobs"
  add_foreign_key "applications", "users"
  add_foreign_key "cover_letter_templates", "users"
  add_foreign_key "jobs", "companies"
  add_foreign_key "user_preferences", "users"
end

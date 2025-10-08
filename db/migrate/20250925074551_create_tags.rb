class CreateTags < ActiveRecord::Migration[7.1]
  def change
    # Use if_not_exists to handle partial creation from previous failed run
    create_table :tags, if_not_exists: true do |t|
      t.string :name, null: false
      t.timestamps
    end

    # MySQL: default collations are case-insensitive, so a normal unique index on name is sufficient
    add_index :tags, :name, unique: true, if_not_exists: true
  end
end
class CreateUsers < ActiveRecord::Migration[7.0]
  def change
    create_table :users do |t|
      t.string :first_name, null: false
      t.string :last_name
      t.string :email, null: false, unique: true
      t.string :password_digest, null: false
      t.integer :role, null: false, default: 0
      t.timestamps
    end

    add_index :users, :email, unique: true
  end
end



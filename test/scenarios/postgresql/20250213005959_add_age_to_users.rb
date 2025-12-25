class AddAgeToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :age, :integer
  end
end

class AddAnnounceableToUsers < ActiveRecord::Migration[8.1]
  def change
    add_reference :users, :announceable, polymorphic: true, null: true
  end
end

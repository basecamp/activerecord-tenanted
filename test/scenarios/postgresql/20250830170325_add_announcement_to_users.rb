class AddAnnouncementToUsers < ActiveRecord::Migration[8.1]
  def change
    add_reference :users, :announcement, null: true
  end
end

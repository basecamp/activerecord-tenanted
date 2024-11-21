# frozen_string_literal: true

class CreateSongs < ActiveRecord::Migration[8.0]
  def change
    create_table :songs do |t|
      t.string :content

      t.timestamps
    end
  end
end

class Note < ApplicationRecord
  has_one_attached :image

  after_update_commit :broadcast_replace

  after_update_commit do
    NoteCheerioJob.perform_later(self) if needs_cheerio?
  end

  def needs_cheerio?
    !body.include?("Cheerio!")
  end
end

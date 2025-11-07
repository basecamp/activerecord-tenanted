class Note < ApplicationRecord
  has_one_attached :image

  after_update_commit :expire_cache_and_broadcast

  after_update_commit do
    NoteCheerioJob.perform_later(self) if needs_cheerio?
  end

  def needs_cheerio?
    !body.include?("Cheerio!")
  end

  private
    def expire_cache_and_broadcast
      Rails.cache.delete(self)
      broadcast_replace
    end
end

# app/models/notification.rb
class Notification < ApplicationRecord
  belongs_to :user
  belongs_to :job

  default_scope { order(created_at: :desc) }

  scope :unread, -> { where(read_at: nil) }

  def read?
    read_at.present?
  end
end

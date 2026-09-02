# app/models/application_event.rb
class ApplicationEvent < ApplicationRecord
  belongs_to :application

  EVENT_TYPES = %w[status_change note follow_up_sent reply_detected].freeze

  validates :event_type, inclusion: { in: EVENT_TYPES }
  validates :body, presence: true, if: -> { event_type == "note" }

  default_scope { order(created_at: :desc) }
end

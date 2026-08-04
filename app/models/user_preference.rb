# app/models/user_preference.rb
class UserPreference < ApplicationRecord
  belongs_to :user

  # Converts "React, Ruby, Developer" into an array: ["react", "ruby", "developer"]
  def keyword_array
    keywords.to_s.downcase.split(",").map(&:strip).reject(&:blank?)
  end
end

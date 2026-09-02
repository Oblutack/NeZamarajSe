# app/models/company.rb
class Company < ApplicationRecord
  has_many :jobs, dependent: :destroy
  belongs_to :last_contacted_by, class_name: "User", optional: true

  validates :name, presence: true, uniqueness: true
end

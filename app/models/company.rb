# app/models/company.rb
class Company < ApplicationRecord
  has_many :jobs, dependent: :destroy
  
  validates :name, presence: true, uniqueness: true
end
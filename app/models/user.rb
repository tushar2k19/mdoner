class User < ApplicationRecord
  has_secure_password
  enum role: { editor: 0, reviewer: 1, 'final-reviewer': 2 }

  validates :first_name, presence: true
  validates :last_name, presence: true
  validates :email, presence: true, uniqueness: true
  validates :phone, presence: true
  validates :password_digest, presence: true
  validates :role, presence: true
end

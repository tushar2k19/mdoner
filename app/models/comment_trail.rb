# app/models/comment_trail.rb
class CommentTrail < ApplicationRecord
  belongs_to :review
  has_many :comments, dependent: :destroy
end

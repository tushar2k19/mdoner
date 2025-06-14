class UserController < ApplicationController
  before_action :authorize_access_request!

  def reviewers
    users = User.where(role: :reviewer) if current_user.role == 'editor'
    users = User.where(role: :final_reviewer) if current_user.role == 'reviewer'

    render json: users.map { |user| user_json(user) }
  end
  private

  def user_json(user)
    {
      id: user.id,
      name: user.full_name,
      email: user.email
    }
  end
end

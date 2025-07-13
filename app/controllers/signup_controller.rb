class SignupController < ApplicationController
  
  def create
    # Extract user parameters
    user_params = params.require(:user).permit(
      :first_name, 
      :last_name, 
      :email, 
      :password, 
      :password_confirmation, 
      :role
    )
    
    # Convert role from string to integer and validate
    if user_params[:role].present?
      role_value = user_params[:role].to_i
      # Validate that the role value is valid for the enum
      unless User.roles.values.include?(role_value)
        return render json: { 
          success: false, 
          errors: ['Invalid role selected'] 
        }, status: :unprocessable_entity
      end
      user_params[:role] = role_value
    end
    
    # Validate password confirmation
    if user_params[:password] != user_params[:password_confirmation]
      return render json: { 
        success: false, 
        errors: ['Password confirmation does not match'] 
      }, status: :unprocessable_entity
    end
    
    # Create user
    user = User.new(user_params)
    
    if user.save
      render json: { 
        success: true, 
        message: 'User created successfully',
        user: {
          id: user.id,
          first_name: user.first_name,
          last_name: user.last_name,
          email: user.email,
          role: user.role
        }
      }
    else
      render json: { 
        success: false, 
        errors: user.errors.full_messages 
      }, status: :unprocessable_entity
    end
  rescue ActionController::ParameterMissing => e
    render json: { 
      success: false, 
      errors: ['Missing required parameters'] 
    }, status: :bad_request
  rescue StandardError => e
    Rails.logger.error "Signup error: #{e.message}"
    render json: { 
      success: false, 
      errors: ['An unexpected error occurred'] 
    }, status: :internal_server_error
  end
end 
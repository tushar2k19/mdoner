Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check
  get 'test_auth' => 'application#test_auth'
  mount ActionCable.server => '/cable'
  # root "refresh#index"

  controller :refresh do
    post 'refresh' => 'refresh#create'
  end

  controller :signin do
    post 'signin' => 'signin#create'
    delete 'signout' => 'signin#destroy'
  end

  controller :signup do
    post 'signup' => 'signup#create'
  end

  controller :task do
    get 'tasks' => 'task#index'
    get 'tasks/review_delay_analytics' => 'task#review_delay_analytics'
    post 'task' => 'task#create'
    put 'task/:id' => 'task#update'
    patch 'task/:id' => 'task#update'
    delete 'task/:id' => 'task#destroy'
    post 'task/:id/send_for_review' => 'task#send_for_review'
    get 'task/:id/review_cycle' => 'task#review_cycle'
    post 'task/:id/approve' => 'task#approve'
    post 'task/:id/complete' => 'task#complete'
    post 'task/:id/mark_incomplete' => 'task#mark_incomplete'
    post 'task/:id/resolve_merge' => 'task#resolve_merge'
    get 'task/:id/merge_analysis' => 'task#merge_analysis'
    post 'task/:id/apply_merge' => 'task#apply_merge'
    get 'tasks/approved' => 'task#approved_tasks'
    get 'tasks/completed' => 'task#completed_tasks'
  end

  namespace :imports do
    post 'dashboard_html/preview' => 'dashboard_html#preview'
    post 'dashboard_html/approve' => 'dashboard_html#approve'
  end

  namespace :meeting_dashboard do
    resources :tasks, only: [:create, :update, :destroy] do
      member do
        get :nodes
      end
    end
    put "tasks/:task_id/nodes/:id", to: "task_nodes#update"
    get "tasks/:task_id/nodes/:id/review_date_extension_events", to: "task_nodes#review_date_extension_events"
  end

  scope path: 'meeting_dashboard', controller: 'meeting_dashboard' do
    get 'draft', action: :draft
    get 'meeting_dates', action: :meeting_dates
    get 'published', action: :published
    get 'draft_settings', action: :draft_settings
    patch 'draft_settings', action: :update_draft_settings
    post 'publish', action: :publish
    post 'reset_draft', action: :reset_draft
    get 'draft_editor_overlay', action: :draft_editor_overlay
    get 'comment_nodes', action: :comment_nodes
    get 'dashboard_node_comments', action: :dashboard_node_comments
    post 'dashboard_node_comments', action: :create_dashboard_node_comment
    post 'assignments', action: :create_assignment
    delete 'assignments/:id', action: :destroy_assignment
    post 'reschedule', action: :reschedule
  end

  controller :comment do
    post 'task/:task_id/comments' => 'comment#create'
    get 'task/:task_id/comments' => 'comment#index'
    put 'task/:task_id/comments/:id' => 'comment#update'
    delete 'task/:task_id/comments/:id' => 'comment#destroy'
    
    # New comment trails routes
    get 'task/:task_id/comment_trails' => 'comment#comment_trails'
    post 'review/:review_id/comments' => 'comment#add_comment_to_review'
    put 'comment/:comment_id/resolve' => 'comment#resolve_comment'
    put 'comment/:comment_id/update' => 'comment#update_review_comment'
    delete 'comment/:comment_id' => 'comment#delete_review_comment'
  end

  controller :notification do
    get 'notifications' => 'notification#index'
    put 'notification/:id/mark_as_read' => 'notification#mark_as_read'
    put 'notifications/mark_all_as_read' => 'notification#mark_all_as_read'
  end

  controller :user do
    get 'users/reviewers' => 'user#reviewers'
    get 'users/final_reviewers' => 'user#final_reviewers'
  end

  # Review routes
  controller :review do
    get 'reviews' => 'review#index'
    get 'review/:id' => 'review#show'
    put 'review/:id' => 'review#update'
    patch 'review/:id' => 'review#update'
    post 'review/:id/approve' => 'review#approve'
    post 'review/:id/reject' => 'review#reject'
    post 'review/:id/forward' => 'review#forward'
    post 'review/:id/remind' => 'review#remind_reviewer'
    get 'review/:id/diff' => 'review#diff'
    get 'review/:id/comments' => 'review#comments'
    get 'versions/:base_version_id/:current_version_id/diff' => 'review#diff'
    get 'reviews/status_breakdown' => 'review#reviewer_status_breakdown'
  end

  controller :tag do
    get 'tags' => 'tag#index'
    post 'tags' => 'tag#create'
  end
  
  # ActionNode routes nested under task versions
  scope 'task_versions/:task_version_id' do
    controller :action_node do
      get 'nodes' => 'action_node#index'
      post 'nodes' => 'action_node#create'
      get 'nodes/:id' => 'action_node#show'
      put 'nodes/:id' => 'action_node#update'
      patch 'nodes/:id' => 'action_node#update'
      delete 'nodes/:id' => 'action_node#destroy'
      get 'nodes/:id/review_date_extension_events' => 'action_node#review_date_extension_events'
      
      # Special node operations
      post 'nodes/add_point' => 'action_node#add_point'
      post 'nodes/add_subpoint' => 'action_node#add_subpoint'
      post 'nodes/:id/toggle_complete' => 'action_node#toggle_complete'
      put 'nodes/:id/move' => 'action_node#move_node'
      post 'nodes/bulk_update' => 'action_node#bulk_update'
      post 'nodes/resort_by_date' => 'action_node#resort_by_date'
    end
  end
end

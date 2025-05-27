Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check
  mount ActionCable.server => '/cable'
  # root "refresh#index"

  controller :refresh do
    post 'refresh' => 'refresh#create'
  end

  controller :signin do
    post 'signin' => 'signin#create'
    delete 'signout' => 'signin#destroy'
  end

  controller :task do
    get 'tasks' => 'task#index'
    post 'task' => 'task#create'
    put 'task/:id' => 'task#update'
    patch 'task/:id' => 'task#update'
    delete 'task/:id' => 'task#destroy'
    post 'task/:id/send_for_review' => 'task#send_for_review'
    post 'task/:id/approve' => 'task#approve'
    post 'task/:id/complete' => 'task#complete'
    post 'task/:id/mark_incomplete' => 'task#mark_incomplete'
    get 'tasks/approved' => 'task#approved_tasks'
    get 'tasks/completed' => 'task#completed_tasks'
  end

  controller :comment do
    post 'task/:task_id/comments' => 'comment#create'
    get 'task/:task_id/comments' => 'comment#index'
    put 'task/:task_id/comments/:id' => 'comment#update'
    delete 'task/:task_id/comments/:id' => 'comment#destroy'
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
end

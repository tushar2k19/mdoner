def show
  @review = Review.find(params[:id])
  diff_data = @review.task_version.diff_with(@review.base_version)
  
  render json: {
    review: serialize_review(@review),
    diff: diff_data,
    nodes: serialize_node_tree_with_diff(@review.task_version.node_tree, diff_data)
  }
end 
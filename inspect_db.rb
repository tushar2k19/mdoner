review = Review.find(20)
puts "--- Review ---"
pp review.attributes

puts "--- Task Version ---"
tv = review.task_version
pp tv.attributes

puts "--- All Action Nodes ---"
tv.all_action_nodes.each do |n|
  puts "ID: #{n.id}, Parent ID: #{n.parent_id}, Reviewer ID: #{n.reviewer_id}, Level: #{n.level}, Content: #{n.content.truncate(30)}"
end

puts "--- Action Nodes (roots) ---"
tv.action_nodes.each do |n|
  puts "ID: #{n.id}, Reviewer ID: #{n.reviewer_id}"
end

puts "--- All Reviews for this Task Version ---"
Review.where(task_version: tv).each do |r|
  pp r.attributes
end
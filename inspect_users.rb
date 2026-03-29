puts '--- Users ---'
User.all.each { |u| puts "ID: #{u.id}, Name: #{u.full_name}, Role: #{u.role}" }
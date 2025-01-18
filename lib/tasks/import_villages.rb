require 'roo'

# Open the xlsx file
file_path = Rails.root.join('app', 'helpers', 'villages.xlsx')
xlsx = Roo::Excelx.new(file_path)

count = 0
(3..xlsx.last_row).each do |i|
  village_name = xlsx.cell(i, 'A').to_s.strip
  block_name = xlsx.cell(i, 'B').to_s.strip

  next if village_name.blank? || block_name.blank?
  block = Block.find_by('LOWER(TRIM(name)) = ?', block_name.downcase.strip)

  if block
    Village.find_or_create_by(name: village_name, block_id: block.id)
    puts "#{count}) -> Added village #{village_name} to block #{block.name}"
  else
    puts "*************************\n"
    puts "#{count})Block #{block_name} not found for village #{village_name}"
    puts "*************************\n"
  end
end

puts "Village import completed."

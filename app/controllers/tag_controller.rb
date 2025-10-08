class TagController < ApplicationController
  def index
    tags = Tag.all

    if ActiveModel::Type::Boolean.new.cast(params[:include_usage])
      usage_counts = TaskTag
        .group(:tag_id)
        .count # => { tag_id => count }

      enriched = tags.map do |t|
        { id: t.id, name: t.name, usage_count: usage_counts[t.id].to_i }
      end

      enriched.sort_by! { |h| [-h[:usage_count], h[:name].downcase] }
      render json: enriched
    else
      render json: tags.select(:id, :name)
    end
  end

  def create
    name = params.require(:name).to_s.strip
    tag = Tag.where('lower(name) = ?', name.downcase).first_or_create!(name: name)
    render json: { id: tag.id, name: tag.name }
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages }, status: :unprocessable_entity
  end
end
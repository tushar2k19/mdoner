# frozen_string_literal: true

class MeetingDashboardController < ApplicationController
  include MeetingDashboardSerialization

  rescue_from ActiveRecord::RecordNotFound do
    render json: { error: "Not found" }, status: :not_found
  end

  before_action :require_meeting_dashboard!
  before_action :require_editor!, only: %i[
    publish reset_draft update_draft_settings
    create_assignment destroy_assignment reschedule
  ]
  # Overlay + comment index are read-only metadata for published packs; editors and reviewers need
  # them on Final (NewFinalDashboard). Mutations stay editor-only above.
  before_action :require_comment_participant!, only: %i[
    draft_editor_overlay comment_nodes
    dashboard_node_comments create_dashboard_node_comment
  ]

  # GET /meeting_dashboard/draft
  # Optional legacy param `date` is ignored: meeting draft is the full living `NewTask` tree.
  # (Filtering by `DATE(created_at) <= date` broke imports when the client sent UTC from
  # `toISOString()` while `created_at` fell on the next UTC calendar day.)
  def draft
    active_tasks, completed_tasks = draft_scope_for_user

    latest = NewDashboardVersion.order(published_at: :desc).first
    latest_payload = if latest
                       {
                         id: latest.id,
                         target_meeting_date: latest.target_meeting_date,
                         published_at: latest.published_at,
                         published_by_id: latest.published_by_id
                       }
                     end

    settings = NewDashboardDraftSetting.global

    render json: {
      active: serialize_meeting_new_tasks(active_tasks),
      completed: serialize_meeting_new_tasks(completed_tasks),
      latest_published: latest_payload,
      draft_settings: {
        target_meeting_date: settings.target_meeting_date
      }
    }
  end

  # GET /meeting_dashboard/meeting_dates
  def meeting_dates
    rows = NewMeetingSchedule.order(meeting_date: :desc).map do |s|
      {
        meeting_date: s.meeting_date,
        new_dashboard_version_id: s.current_new_dashboard_version_id,
        set_at: s.set_at
      }
    end
    render json: { meeting_dates: rows }
  end

  # GET /meeting_dashboard/published?meeting_date=YYYY-MM-DD
  # OR GET /meeting_dashboard/published?new_dashboard_version_id=&dashboard_version_id=
  # (either version param loads that snapshot directly — for Review Hub deep links.)
  def published
    version_id = params[:new_dashboard_version_id].presence || params[:dashboard_version_id].presence

    if version_id.present?
      version = NewDashboardVersion.includes(new_dashboard_snapshot_tasks: { new_dashboard_snapshot_action_nodes: :reviewer })
                                   .find_by(id: version_id)
      unless version
        return render json: {
          tasks: [],
          empty: true,
          meeting_date: nil,
          meeting_dashboard_version_id: nil,
          schedule_meeting_date: nil,
          target_meeting_date: nil,
          published_at: nil
        }
      end

      pointer = NewMeetingSchedule.where(current_new_dashboard_version_id: version.id).order(meeting_date: :desc).first
      schedule_meeting_date = pointer&.meeting_date
      meeting_date_label = schedule_meeting_date || version.target_meeting_date

      return render_published_json(version, meeting_date_label, schedule_meeting_date: schedule_meeting_date)
    end

    meeting_date = if params[:meeting_date].present?
                     Date.parse(params[:meeting_date])
                   else
                     NewMeetingSchedule.order(meeting_date: :desc).first&.meeting_date || Date.current
                   end

    schedule = NewMeetingSchedule.find_by(meeting_date: meeting_date)
    unless schedule
      return render json: {
        tasks: [],
        empty: true,
        meeting_date: meeting_date,
        meeting_dashboard_version_id: nil,
        schedule_meeting_date: nil,
        target_meeting_date: nil,
        published_at: nil
      }
    end

    version = NewDashboardVersion.includes(new_dashboard_snapshot_tasks: { new_dashboard_snapshot_action_nodes: :reviewer })
                                 .find_by(id: schedule.current_new_dashboard_version_id)
    unless version
      return render json: {
        tasks: [],
        empty: true,
        meeting_date: meeting_date,
        meeting_dashboard_version_id: nil,
        schedule_meeting_date: nil,
        target_meeting_date: nil,
        published_at: nil
      }
    end

    render_published_json(version, meeting_date, schedule_meeting_date: meeting_date)
  end

  # GET /meeting_dashboard/draft_settings
  def draft_settings
    s = NewDashboardDraftSetting.global
    render json: { target_meeting_date: s.target_meeting_date }
  end

  # PATCH /meeting_dashboard/draft_settings  params: { target_meeting_date: "YYYY-MM-DD" }
  def update_draft_settings
    s = NewDashboardDraftSetting.global
    if params[:target_meeting_date].present?
      s.target_meeting_date = Date.parse(params[:target_meeting_date].to_s)
    end
    s.updated_by = current_user
    s.save!
    render json: { target_meeting_date: s.target_meeting_date }
  end

  # POST /meeting_dashboard/publish  params: { target_meeting_date: optional }
  def publish
    settings = NewDashboardDraftSetting.global
    meeting_date = if params[:target_meeting_date].present?
                     Date.parse(params[:target_meeting_date].to_s)
                   else
                     settings.target_meeting_date || Date.current
                   end

    version = MeetingDashboard::Publisher.call!(user: current_user, target_meeting_date: meeting_date)

    settings.update!(target_meeting_date: meeting_date, updated_by: current_user)

    render json: {
      success: true,
      new_dashboard_version_id: version.id,
      target_meeting_date: version.target_meeting_date,
      published_at: version.published_at
    }
  rescue ArgumentError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # POST /meeting_dashboard/reset_draft
  def reset_draft
    MeetingDashboard::DraftResetter.call!(user: current_user)
    render json: { success: true }
  rescue ArgumentError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # GET /meeting_dashboard/draft_editor_overlay?new_dashboard_version_id=
  def draft_editor_overlay
    version = resolve_published_version_for_overlay
    render json: MeetingDashboard::EditorOverlayBuilder.call(version)
  end

  # GET /meeting_dashboard/comment_nodes?new_dashboard_version_id=
  def comment_nodes
    version = resolve_published_version_for_overlay
    list = version ? MeetingDashboard::CommentNodesIndex.call(version) : []
    render json: { new_dashboard_version_id: version&.id, nodes: list }
  end

  # GET /meeting_dashboard/dashboard_node_comments?new_dashboard_version_id=&stable_node_id=
  def dashboard_node_comments
    version = NewDashboardVersion.find(params.require(:new_dashboard_version_id))
    snap = find_snapshot_node!(version, params.require(:stable_node_id))
    rows = NewDashboardNodeComment.where(new_dashboard_version_id: version.id,
                                         new_dashboard_snapshot_action_node_id: snap.id)
                                  .includes(:user)
                                  .order(:created_at)
    render json: {
      new_dashboard_version_id: version.id,
      stable_node_id: snap.stable_node_id,
      comments: rows.map { |c| serialize_dashboard_node_comment(c) }
    }
  end

  # POST /meeting_dashboard/dashboard_node_comments
  # params: new_dashboard_version_id, stable_node_id, body
  def create_dashboard_node_comment
    version = NewDashboardVersion.find(params.require(:new_dashboard_version_id))
    snap = find_snapshot_node!(version, params.require(:stable_node_id))
    body = params.require(:body).to_s.strip
    raise ArgumentError, "body is blank" if body.blank?

    c = NewDashboardNodeComment.create!(
      new_dashboard_version: version,
      new_dashboard_snapshot_action_node: snap,
      user: current_user,
      body: body
    )
    render json: { success: true, comment: serialize_dashboard_node_comment(c) }
  rescue ArgumentError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # POST /meeting_dashboard/assignments
  # params: new_dashboard_version_id, stable_node_id, user_id
  def create_assignment
    version = NewDashboardVersion.find(params.require(:new_dashboard_version_id))
    snap = find_snapshot_node!(version, params.require(:stable_node_id))
    user = User.find(params.require(:user_id))

    assignment = NewDashboardAssignment.find_by(
      new_dashboard_version_id: version.id,
      new_dashboard_snapshot_action_node_id: snap.id,
      user_id: user.id
    )
    assignment ||= NewDashboardAssignment.create!(
      new_dashboard_version: version,
      new_dashboard_snapshot_action_node: snap,
      user: user
    )
    render json: { success: true, assignment: serialize_assignment(assignment) }
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.join(", ") }, status: :unprocessable_entity
  end

  # DELETE /meeting_dashboard/assignments/:id
  def destroy_assignment
    a = NewDashboardAssignment.find(params.require(:id))
    a.destroy!
    render json: { success: true }
  end

  # POST /meeting_dashboard/reschedule
  # params: from_meeting_date, to_meeting_date, optional new_dashboard_version_id
  def reschedule
    schedule = MeetingDashboard::Rescheduler.call!(
      actor: current_user,
      from_meeting_date: params.require(:from_meeting_date),
      to_meeting_date: params.require(:to_meeting_date),
      new_dashboard_version_id: params[:new_dashboard_version_id]
    )
    render json: {
      success: true,
      meeting_date: schedule.meeting_date,
      new_dashboard_version_id: schedule.current_new_dashboard_version_id
    }
  rescue ArgumentError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def render_published_json(version, meeting_date_label, schedule_meeting_date:)
    tasks_json = serialize_meeting_snapshot_tasks(version)

    render json: {
      tasks: tasks_json,
      empty: tasks_json.empty?,
      meeting_date: meeting_date_label,
      meeting_dashboard_version_id: version.id,
      target_meeting_date: version.target_meeting_date,
      published_at: version.published_at,
      schedule_meeting_date: schedule_meeting_date
    }
  end

  def require_meeting_dashboard!
    return if Rails.configuration.x.meeting_dashboard_enabled

    render json: { error: "Meeting dashboard disabled" }, status: :not_found
  end

  def require_editor!
    return if current_user&.role.to_s == "editor"

    render json: { error: "Forbidden" }, status: :forbidden
  end

  def draft_scope_for_user
    base = NewTask.includes(:editor, :tags, new_action_nodes: :reviewer)

    case current_user.role.to_s
    when "editor"
      active = base.where.not(status: :completed)
      completed = base.where(status: :completed).order(completed_at: :desc)
      [active, completed]
    else
      [NewTask.none, NewTask.none]
    end
  end

  def require_comment_participant!
    role = current_user&.role.to_s
    return if %w[editor reviewer final_reviewer].include?(role)

    render json: { error: "Forbidden" }, status: :forbidden
  end

  def resolve_published_version_for_overlay
    vid = params[:new_dashboard_version_id].presence || params[:version_id].presence
    if vid.present?
      NewDashboardVersion.find_by(id: vid)
    else
      NewDashboardVersion.order(published_at: :desc).first
    end
  end

  def find_snapshot_node!(version, stable_node_id)
    raise ArgumentError, "stable_node_id required" if stable_node_id.blank?

    snap = NewDashboardSnapshotActionNode.find_by(
      new_dashboard_version_id: version.id,
      stable_node_id: stable_node_id.to_s
    )
    raise ActiveRecord::RecordNotFound unless snap

    snap
  end

  def serialize_dashboard_node_comment(c)
    {
      "id" => c.id,
      "body" => c.body,
      "created_at" => c.created_at.iso8601,
      "user_id" => c.user_id,
      "user_name" => c.user&.full_name
    }
  end

  def serialize_assignment(a)
    {
      "id" => a.id,
      "new_dashboard_version_id" => a.new_dashboard_version_id,
      "new_dashboard_snapshot_action_node_id" => a.new_dashboard_snapshot_action_node_id,
      "user_id" => a.user_id,
      "user_name" => a.user&.full_name
    }
  end
end

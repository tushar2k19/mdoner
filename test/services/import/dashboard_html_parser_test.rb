# frozen_string_literal: true

require 'test_helper'

class DashboardHtmlParserTest < ActiveSupport::TestCase
  test 'extracts tasks and parses action cell lists' do
    html = File.read(Rails.root.join('test/fixtures/files/dashboard_small.html'))
    tasks = Import::DashboardHtmlParser.parse(html)

    assert_equal 1, tasks.size
    t1 = tasks.first
    assert_equal 1, t1[:sn]
    assert_equal 'IFD', t1[:sector_division]
    assert_includes t1[:description], 'Monthly'
    assert_equal 'All JS', t1[:responsibility]

    nodes = t1[:nodes]
    assert nodes.is_a?(Array)
    assert nodes.size >= 3

    root = nodes.find { |n| n[:level] == 1 }
    assert root
    assert_equal 'decimal', root[:list_style]
    assert_includes root[:content], 'Slow expenditure'

    alpha = nodes.find { |n| n[:list_style] == 'lower-alpha' }
    assert alpha
    assert_equal 2, alpha[:level]

    roman = nodes.find { |n| n[:list_style] == 'lower-roman' }
    assert roman
    assert_equal 3, roman[:level]
  end

  test 'converts embedded tables to resizable-table html' do
    html = File.read(Rails.root.join('test/fixtures/files/dashboard_small.html'))
    tasks = Import::DashboardHtmlParser.parse(html)
    joined = tasks.first[:nodes].map { |n| n[:content] }.join("\n")
    assert_includes joined, 'class="resizable-table"'
  end

  test 'approve endpoint creates task, version, and nodes' do
    editor = build_user(role: :editor, first_name: "Import", last_name: "Editor")

    html = File.read(Rails.root.join('test/fixtures/files/dashboard_small.html'))
    extracted = Import::DashboardHtmlParser.parse(html).first

    # Simulate controller params shape.
    nodes = extracted[:nodes].map { |n| n.transform_keys(&:to_s) }
    task_payload = {
      'sector_division' => extracted[:sector_division],
      'description' => extracted[:description],
      'responsibility' => extracted[:responsibility],
      'sn' => extracted[:sn]
    }

    controller = Imports::DashboardHtmlController.new
    controller.define_singleton_method(:current_user) { editor }

    result = controller.send(:create_task_with_nodes!, task_payload, nodes)
    assert result[:success]

    task = Task.find(result[:task_id])
    assert_equal editor.id, task.editor_id
    assert_equal 'draft', task.status
    assert task.current_version_id

    version = TaskVersion.find(result[:task_version_id])
    assert_equal task.id, version.task_id
    assert_equal 'draft', version.status

    assert version.all_action_nodes.count >= 3
  end
end


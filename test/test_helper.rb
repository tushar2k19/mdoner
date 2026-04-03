ENV["RAILS_ENV"] ||= "test"

if ENV["COVERAGE"] == "true"
  require "simplecov"
  SimpleCov.start "rails" do
    add_filter "/test/"
    add_filter "/config/"
    add_filter "/vendor/"
  end
end

require_relative "../config/environment"
require "rails/test_help"
require "securerandom"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    # Add more helper methods to be used by all tests here...

    def build_user(role:, first_name:, last_name:)
      User.create!(
        first_name: first_name,
        last_name: last_name,
        email: "#{first_name.downcase}.#{SecureRandom.hex(4)}@example.com",
        password: "Password!23",
        role: role
      )
    end

    def build_task_with_node_hierarchy
      editor = build_user(role: :editor, first_name: "Editor", last_name: "One")
      reviewer = build_user(role: :reviewer, first_name: "Reviewer", last_name: "Two")

      task = Task.create!(
        sector_division: "Infrastructure",
        description: "Demo task for hierarchy tests",
        original_date: Date.today,
        responsibility: "Planning Dept",
        review_date: Date.today,
        editor: editor
      )

      version = TaskVersion.create!(
        task: task,
        editor: editor,
        version_number: 1,
        status: "draft"
      )

      point1 = version.all_action_nodes.create!(
        content: "<point 1>",
        level: 1,
        list_style: "decimal",
        node_type: "point",
        position: 1
      )

      subpoint1 = version.all_action_nodes.create!(
        content: "<subpoint 1>",
        parent: point1,
        level: 2,
        list_style: "lower-alpha",
        node_type: "subpoint",
        position: 1
      )

      subpoint2 = version.all_action_nodes.create!(
        content: "<subpoint 2>",
        parent: point1,
        level: 2,
        list_style: "lower-alpha",
        node_type: "subpoint",
        position: 2
      )

      point2 = version.all_action_nodes.create!(
        content: "<point 2>",
        level: 1,
        list_style: "decimal",
        node_type: "point",
        position: 2,
        reviewer: reviewer
      )

      point3 = version.all_action_nodes.create!(
        content: "<point 3>",
        level: 1,
        list_style: "decimal",
        node_type: "point",
        position: 3
      )

      subpoint3 = version.all_action_nodes.create!(
        content: "<subpoint 3>",
        parent: point3,
        level: 2,
        list_style: "lower-alpha",
        node_type: "subpoint",
        position: 1
      )

      subsubpoint1 = version.all_action_nodes.create!(
        content: "<sub-subpoint 1>",
        parent: subpoint3,
        level: 3,
        list_style: "lower-roman",
        node_type: "subsubpoint",
        position: 1,
        reviewer: reviewer
      )

      task.update!(current_version: version)

      {
        task: task,
        version: version,
        editor: editor,
        reviewer: reviewer,
        nodes: {
          point1: point1,
          subpoint1: subpoint1,
          subpoint2: subpoint2,
          point2: point2,
          point3: point3,
          subpoint3: subpoint3,
          subsubpoint1: subsubpoint1
        }
      }
    end
  end
end

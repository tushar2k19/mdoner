# Task Dashboard Performance: Problem and Solution

This document describes a performance problem in the task/review dashboards and how it was solved through eager loading, in-memory tree building, and single-pass serialization.

---

## 1. The Problem

### 1.1 Symptoms

- **Slow dashboard loads**: Editor Dashboard, Reviewer Dashboard, Completed Tasks, and Final Dashboard (approved tasks) were slow when many tasks were listed.
- **High database load**: Each task’s serialization triggered many extra queries instead of a small, bounded set.

### 1.2 Root Causes

#### A. N+1 queries on task lists

Task index endpoints loaded tasks with only:

```ruby
Task.includes(:editor, :current_version)
```

So for each task we then needed:

- **Tags** → one query per task when serializing `task.tags`.
- **Action nodes** → when building the version’s node tree, each `TaskVersion#node_tree` called `action_nodes.order(:position)` and then recursively loaded **children** per node, causing many queries per version.
- **Reviewers** → `Task#reviewer_info` used `current_version.all_action_nodes.joins(:reviewer)...`, adding more queries per task.
- **Parent / reviewer on nodes** → any code touching `node.parent` or `node.reviewer` caused further queries per node.

Result: **1 query for the task list + N × (tags + version + nodes + children + reviewers + …)** — classic N+1 (and N+M+…) behaviour.

#### B. N+1 from `display_counter` on every node

Each action node shows a list counter (e.g. `1`, `a`, `i`, `•`) based on its position among **siblings with the same `list_style`**. That was implemented as:

```ruby
# app/models/action_node.rb
def display_counter
  siblings_before_and_including_me = siblings_with_same_style.where('position <= ?', position).order(:position)
  counter_position = siblings_before_and_including_me.count
  # ... then format by list_style (decimal, lower-alpha, lower-roman, bullet)
end
```

So **every** node triggered at least one extra query (siblings + count). For a version with dozens or hundreds of nodes, we got:

- One call to `display_counter` when building **JSON** (`action_nodes` with `display_counter`).
- Another when building **HTML** (`html_formatted_content` → `html_formatted_display` → `display_counter`).

So we were doing **2 × (number of nodes)** extra queries per task version, plus the tree/children/reviewer loads above.

#### C. Redundant work and inconsistent counters

- The **node tree** was built in the model by querying the DB (e.g. `action_nodes.order(:position)` and recursive `node.children.order(:position)`), so the same tree could be reconstructed multiple times in different code paths.
- **Display counters** were computed independently for JSON and for HTML. That meant:
  - Double work.
  - Risk of inconsistency if any logic diverged (e.g. ordering or list_style grouping).

#### D. Tree building in the model triggered more queries

`TaskVersion#node_tree` used to call something like:

```ruby
def build_tree_structure(nodes)
  nodes.map do |node|
    {
      node: node,
      children: build_tree_structure(node.children.order(:position))  # query per node!
    }
  end
end
```

So each node caused a new query for its children. With a deep or wide tree, this multiplied the number of queries per version.

---

## 2. Solution Overview

We fixed this with three main ideas:

1. **Eager load** everything needed for the dashboard in the controller (tasks, versions, tags, action nodes, reviewer, parent).
2. **Build the node tree once in memory** from the preloaded collection (no extra queries).
3. **Compute display counters once** and reuse the same values for both JSON and HTML.

That way, a single request does a **bounded number of queries** (tasks + includes) and then does the rest in Ruby with the already-loaded data.

---

## 3. How We Solved It

### 3.1 Eager loading in controllers

**TaskController** (index, completed_tasks, approved_tasks, etc.) now loads tasks with:

```ruby
Task.includes(
  :editor,
  :tags,
  current_version: {
    all_action_nodes: [:reviewer, :parent]
  }
).where(...)
```

So for each task we get, in one go:

- `editor`, `tags`, `current_version`
- All `action_nodes` for that version, with `reviewer` and `parent` preloaded.

**ReviewController** (list and `set_review`) now includes:

```ruby
task_version: [
  :task, :editor,
  { all_action_nodes: [:reviewer, :parent] }
]
```

So when we serialize a review and its task version’s nodes, we don’t hit the DB again for nodes, parents, or reviewers.

### 3.2 In-memory node tree (no extra queries)

**TaskVersion** no longer builds the tree by querying the DB per node. It assumes `all_action_nodes` is already loaded (e.g. by the controller) and builds the tree in memory:

```ruby
def node_tree
  all_nodes = all_action_nodes.to_a
  build_tree_structure_in_memory(all_nodes)
end

def build_tree_structure_in_memory(nodes)
  nodes_by_parent = nodes.group_by(&:parent_id)
  build_subtree = lambda do |parent_id|
    (nodes_by_parent[parent_id] || []).sort_by(&:position).map do |node|
      { node: node, children: build_subtree.call(node.id) }
    end
  end
  build_subtree.call(nil)  # roots
end
```

- One pass over the flat list to group by `parent_id`.
- Recursion only over in-memory arrays.
- **No** `node.children.order(:position)` or similar — zero extra queries for the tree.

### 3.3 Single-pass display counters and shared use in JSON + HTML

Display counters depend on **sibling order within the same `list_style`**. Instead of querying per node, we:

1. Build the tree once (in memory, as above).
2. In the **controller**, run a single recursive pass over that tree and assign `display_counter` to each node (group siblings by `list_style`, sort by `position`, assign 1, 2, 3… and map to "1", "a", "i", "•" etc.).
3. Store the result in a **counters map** `node_id => display_counter`.
4. Use that map for:
   - **JSON**: when serializing `action_nodes`, pass the pre-calculated counter into each node.
   - **HTML**: pass the same map into `html_formatted_content(counters_map)` so each node’s `html_formatted_display` gets `precalculated_counter` and never calls `display_counter`.

So we compute each node’s counter **once** and reuse it everywhere. No per-node DB for siblings, and JSON/HTML stay in sync.

Implementation details in the controller:

- `calculate_display_counters(tree)` walks the tree, groups siblings by `list_style`, sorts by `position`, assigns counters (including roman numerals via `to_roman_numeral`), and stores `display_counter` on each tree item.
- `serialize_flat_with_counters(tree)` produces the flat hierarchy for the API using `serialize_node_with_counter(node, tree_item[:display_counter])`.
- `html_content = current_version.html_formatted_content(counters_map)` uses that same map so `format_html_tree_nodes(..., counters_map)` can call `node.html_formatted_display(counters_map[node.id])` and avoid `display_counter` entirely.

### 3.4 Optional pre-calculated counter in the model

**ActionNode** remains backwards compatible: callers that don’t have a pre-calculated counter can still rely on the old behaviour:

```ruby
def html_formatted_display(precalculated_counter = nil)
  counter = precalculated_counter || display_counter
  # ... rest of HTML formatting
end
```

So:

- **Dashboard path**: controller passes the counter from the map → no DB.
- **Other callers** (e.g. single node or ad-hoc): omit the argument → fall back to `display_counter` (and its query).

**TaskVersion** does the same: `html_formatted_content(counters_map = nil)` and `format_html_tree_nodes(tree_nodes, counters_map = nil)` pass the map through when present.

### 3.5 Reviewer info without extra queries

**Task#reviewer_info** used to use a fresh query over `all_action_nodes` and `joins(:reviewer)`. It now uses the preloaded association and in-memory work:

```ruby
def reviewer_info
  return nil unless current_version
  nodes = current_version.all_action_nodes.to_a
  reviewers = nodes.map(&:reviewer).compact.map(&:full_name).uniq.sort
  reviewers.any? ? reviewers.join(', ') : nil
end
```

So when the controller has eager-loaded `current_version` and `all_action_nodes: [:reviewer]`, this adds no queries.

### 3.6 Tags serialization

Tags are now serialized from the preloaded collection so we don’t trigger a new query per task:

```ruby
'tags' => task.tags.to_a.map { |t| { id: t.id, name: t.name } }
```

With `includes(:tags)`, this uses the in-memory list.

### 3.7 Response shape: `action_to_be_taken` as HTML

The API now returns the **pre-rendered HTML** for “action to be taken” so the frontend doesn’t have to rebuild it:

- Controller builds the tree once, computes counters once, then calls `current_version.html_formatted_content(counters_map)`.
- That string is sent as `action_to_be_taken` in the task payload.

So the heavy work (tree + counters + HTML) is done once per task on the server, with no duplicate queries.

---

## 4. Files Changed (Summary)

| Area | File | Change |
|------|------|--------|
| Controllers | `task_controller.rb` | Eager load `tags`, `current_version => all_action_nodes => [:reviewer, :parent]` on all task list actions; single-pass serialization with `calculate_display_counters`, `serialize_flat_with_counters`, `serialize_node_with_counter`, `to_roman_numeral`; `action_to_be_taken` set to pre-rendered HTML; tags from preloaded association. |
| Controllers | `review_controller.rb` | Eager load `task_version => all_action_nodes => [:reviewer, :parent]` (and existing includes) for list and `set_review`. |
| Models | `task_version.rb` | `node_tree` uses `build_tree_structure_in_memory(all_action_nodes.to_a)`; `html_formatted_content(counters_map = nil)` and `format_html_tree_nodes(..., counters_map)` accept optional counters map; removed DB-based `build_tree_structure`. |
| Models | `action_node.rb` | `html_formatted_display(precalculated_counter = nil)` uses pre-calculated counter when given, else `display_counter`. |
| Models | `task.rb` | `reviewer_info` uses `current_version.all_action_nodes.to_a` and preloaded `reviewer` (no extra query). |
| Tests | `test_helper.rb` | Helpers like `build_user`, `build_task_with_node_hierarchy` for tests; `fixtures :all` removed where appropriate. |
| Config | `database.yml` / `schema.rb` | Test DB name and foreign key settings (unrelated to this performance work). |

---

## 5. Takeaways

- **Measure first**: The problem showed up as slow dashboards and many queries; fixing N+1 and redundant work had the largest impact.
- **Eager load at the boundary**: Controllers decide what the request needs and use `includes` so one (or a few) queries load the full graph (tasks, versions, nodes, reviewer, parent, tags).
- **One source of truth in memory**: Build the tree once from the preloaded nodes; compute counters once; reuse for both JSON and HTML so behaviour is consistent and cheap.
- **Models stay flexible**: `html_formatted_display(precalculated_counter = nil)` and `html_formatted_content(counters_map = nil)` keep the fast path in the controller while leaving the model usable from other callers that don’t have a pre-calculated map.

This pattern (eager load → in-memory tree → single-pass counters → reuse in JSON + HTML) is the template for any future endpoints that need to serialize task versions with action node trees and display counters without N+1 or duplicate work.

# README

This README would normally document whatever steps are necessary to get the
application up and running.

## Meeting-centric dashboard (feature flag)

- **Production / default (`application.rb`):** `FEATURE_MEETING_DASHBOARD` defaults to **off**; set `FEATURE_MEETING_DASHBOARD=true` in `.env` (see `.env.example`) to enable parallel `new_*` tables and `/meeting_dashboard/*` APIs.
- **Development (`config/environments/development.rb`):** defaults to **on** so local QA hits meeting APIs without extra env; set `FEATURE_MEETING_DASHBOARD=false` to disable.
- When disabled, the app uses legacy `tasks` / `task_versions` / `action_nodes` only for dashboard flows.

Things you may want to cover:

* Ruby version

* System dependencies

* Configuration

* Database creation

* Database initialization

* How to run the test suite

* Services (job queues, cache servers, search engines, etc.)

* Deployment instructions

* ...

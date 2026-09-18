# frozen_string_literal: true

appraise "rails-8-1" do
  gem "rails", "~> 8.1.0"

  # json 3.0 made ::JSON.parse's options keyword-only, which breaks
  # ActiveSupport::JSON.decode in Rails 8.1.3.1. Remove this pin once a Rails 8.1
  # release carries the backport from https://github.com/rails/rails/pull/58601.
  gem "json", "< 3"
end

appraise "rails-edge" do
  gem "rails", github: "rails/rails", branch: "main"
end

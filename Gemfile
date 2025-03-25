# frozen_string_literal: true

source "https://rubygems.org"

gemspec

group :development do
  gem "rails", github: "rails/rails", branch: "main"
  gem "sqlite3", "2.6.0"
  gem "debug", "1.10.0"
  gem "minitest-parallel_fork", "2.0.0"
end

group :rubocop do
  gem "rubocop-minitest", "0.37.1", require: false
  gem "rubocop-packaging", "0.6.0", require: false
  gem "rubocop-performance", "1.24.0", require: false
  gem "rubocop-rails", "2.30.3", require: false
  gem "rubocop-rake", "0.7.1", require: false
end

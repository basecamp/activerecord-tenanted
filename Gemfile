# frozen_string_literal: true

source "https://rubygems.org"

gemspec

group :development do
  gem "rails", github: "rails/rails", branch: "main"
  gem "sqlite3", "2.7.1"
  gem "debug", "1.11.0"
  gem "minitest-parallel_fork", "2.0.0"
end

group :rubocop do
  gem "rubocop-minitest", "0.38.1", require: false
  gem "rubocop-packaging", "0.6.0", require: false
  gem "rubocop-performance", "1.25.0", require: false
  gem "rubocop-rails", "2.32.0", require: false
  gem "rubocop-rake", "0.7.1", require: false
end

# dependencies needed by the test/smarty integration tests
gem "capybara"
gem "importmap-rails"
gem "jbuilder"
gem "propshaft"
gem "puma", ">= 5.0"
gem "selenium-webdriver"
gem "solid_cable"
gem "solid_cache"
gem "solid_queue"
gem "stimulus-rails"
gem "tailwindcss-rails"
gem "turbo-rails"

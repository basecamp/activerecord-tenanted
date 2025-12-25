ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    # Use PARALLEL_WORKERS env var if set, otherwise use number of processors
    # Disable parallelization when workers is 1 to avoid test worker ID suffix issues
    workers = if ENV["PARALLEL_WORKERS"]
      worker_count = ENV["PARALLEL_WORKERS"].to_i
      worker_count > 1 ? worker_count : 0 # 0 means disable parallelization
    else
      :number_of_processors
    end
    parallelize(workers: workers) unless workers == 0

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
  end
end

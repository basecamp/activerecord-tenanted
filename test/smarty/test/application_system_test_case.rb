require "test_helper"

Capybara.server = :puma, { Silent: true }

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  if ENV["CHROMEDRIVER_PATH"]
    driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1400 ] do |driver_option|
      driver_option.add_argument("--disable-dev-shm-usage")
      driver_option.add_argument("--no-sandbox")
    end

    Selenium::WebDriver::Chrome::Service.driver_path = ENV["CHROMEDRIVER_PATH"]
  else
    driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1400 ] do |driver_option|
      driver_option.add_argument("--disable-dev-shm-usage")
      driver_option.add_argument("--no-sandbox")
    end
  end
end

ENV["RAILS_ENV"] ||= "test"
ENV["JWT_SECRET"] ||= "test_jwt_secret"
ENV["CMSV6_BASE_URL"] ||= "https://cmsv6.example.test"
ENV["CMSV6_ACCOUNT"] ||= "test_account"
ENV["CMSV6_PASSWORD"] ||= "test_password"

require File.expand_path("../config/environment", __dir__)
abort("The Rails environment is running in production mode!") if Rails.env.production?

require "rspec/rails"

begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => error
  abort error.to_s.strip
end

RSpec.configure do |config|
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!
end

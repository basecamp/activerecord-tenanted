# frozen_string_literal: true

class TenantedApplicationRecord < ActiveRecord::Base
  self.abstract_class = true
  tenanted
end

class User < TenantedApplicationRecord
end

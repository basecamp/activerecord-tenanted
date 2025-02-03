# frozen_string_literal: true

class TenantedApplicationRecord < ActiveRecord::Base
  self.abstract_class = true

  tenanted "tenanted"
end

class User < TenantedApplicationRecord
end

class SharedApplicationRecord < ActiveRecord::Base
  primary_abstract_class

  connects_to database: { writing: :shared }
end

class Announcement < SharedApplicationRecord
end

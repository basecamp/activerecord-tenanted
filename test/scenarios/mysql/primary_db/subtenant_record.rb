# frozen_string_literal: true

class TenantedApplicationRecord < ActiveRecord::Base
  primary_abstract_class

  tenanted
end

class User < ActiveRecord::Base
  subtenant_of "TenantedApplicationRecord"
end

class Post < ActiveRecord::Base
  subtenant_of "TenantedApplicationRecord"
end

class SharedApplicationRecord < ActiveRecord::Base
  self.abstract_class = true

  connects_to database: { writing: :shared }
end

class Announcement < SharedApplicationRecord
end

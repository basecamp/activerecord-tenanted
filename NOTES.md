
# Get rid of the protoshard and while_untenanted (this may be hard!)

I spent a while this week trying to unwind this, and the yak shave looks like

1. get rid of the shard and while_untenanted; and raise exception if shard is nil
2. change TestCase initialization to defer setting the shard until the before test hook
3. set new class attribute self.use_default_tenant=false in the FirstRunsControllerTest
4. watch fixtures explode in those tests because there's no tenant set

It looks like skipping fixtures or modifying them to deal with a missing database connection is going to be very invasive. So I'm going to prioritize this below the developer experience stuff.

For posterity, the stack walkback for the failure in the FirstRunsController is:

```
Error:
FirstRunsControllerTest#test_show:
ActiveRecord::Tenanted::NoCurrentTenantError: Cannot use an untenanted ActiveRecord::Base connection. If you have a model that inherits directly from ActiveRecord::Base, make sure to use 'tenanted_with'. In development, you may see this error if constant reloading is not being done properly.
    /home/flavorjones/Work/basecamp/active_record-tenanted/lib/active_record/tenanted/database_configurations.rb:26:in `new_connection'
    /home/flavorjones/code/oss/rails/activerecord/lib/active_record/connection_adapters/abstract/connection_pool.rb:697:in `new_connection'
    /home/flavorjones/code/oss/rails/activerecord/lib/active_record/connection_adapters/abstract/connection_pool.rb:934:in `checkout_new_connection'
    /home/flavorjones/code/oss/rails/activerecord/lib/active_record/connection_adapters/abstract/connection_pool.rb:907:in `try_to_checkout_new_connection'
    /home/flavorjones/code/oss/rails/activerecord/lib/active_record/connection_adapters/abstract/connection_pool.rb:864:in `acquire_connection'
    /home/flavorjones/code/oss/rails/activerecord/lib/active_record/connection_adapters/abstract/connection_pool.rb:561:in `checkout'
    /home/flavorjones/code/oss/rails/activerecord/lib/active_record/connection_adapters/abstract/connection_pool.rb:418:in `with_connection'
    /home/flavorjones/code/oss/rails/activerecord/lib/active_record/fixtures.rb:683:in `block in insert'
    /home/flavorjones/code/oss/rails/activerecord/lib/active_record/fixtures.rb:674:in `each'
    /home/flavorjones/code/oss/rails/activerecord/lib/active_record/fixtures.rb:674:in `insert'
    /home/flavorjones/code/oss/rails/activerecord/lib/active_record/fixtures.rb:660:in `read_and_insert'
    /home/flavorjones/code/oss/rails/activerecord/lib/active_record/fixtures.rb:605:in `create_fixtures'
    /home/flavorjones/code/oss/rails/activerecord/lib/active_record/test_fixtures.rb:282:in `load_fixtures'
    /home/flavorjones/code/oss/rails/activerecord/lib/active_record/test_fixtures.rb:154:in `setup_fixtures'
    /home/flavorjones/code/oss/rails/activerecord/lib/active_record/test_fixtures.rb:10:in `before_setup'
    /home/flavorjones/code/oss/rails/actioncable/lib/action_cable/test_helper.rb:15:in `before_setup'
    /home/flavorjones/Work/basecamp/active_record-tenanted/lib/active_record/tenanted/railtie.rb:51:in `before_setup'
    /home/flavorjones/code/oss/rails/activesupport/lib/active_support/testing/setup_and_teardown.rb:40:in `before_setup'
    /home/flavorjones/code/oss/rails/actionpack/lib/action_dispatch/testing/integration.rb:349:in `before_setup'
    /home/flavorjones/code/oss/rails/activejob/lib/active_job/test_helper.rb:53:in `before_setup'
    /home/flavorjones/code/oss/rails/railties/lib/rails/test_help.rb:45:in `before_setup'
```

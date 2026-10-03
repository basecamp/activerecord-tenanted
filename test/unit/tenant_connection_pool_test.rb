# frozen_string_literal: true

require "thread"
require "timeout"
require "test_helper"

describe ActiveRecord::Tenanted::TenantConnectionPool do
  with_scenario(:primary_named_db, :primary_record) do
    let(:create_pool) do
      ->(tenant) do
        TenantedApplicationRecord.create_tenant(tenant) { User.count }
        TenantedApplicationRecord.with_tenant(tenant) { User.connection_pool }
      end
    end

    let(:prepare_database) do
      ->(tenant) do
        config = base_config.new_tenant_config(tenant)
        config.config_adapter.create_database
        ActiveRecord::Tenanted::DatabaseTasks.new(base_config).migrate_tenant(tenant)
        config
      end
    end

    let(:with_monitor_held_by_another_thread) do
      lambda do |monitor, &block|
        acquired = Queue.new
        release = Queue.new
        owner = Thread.new do
          entered = false
          if monitor.respond_to?(:mon_enter, true)
            monitor.__send__(:mon_enter)
          else
            monitor.enter
          end
          entered = true
          acquired << true
          release.pop
        ensure
          if entered
            if monitor.respond_to?(:mon_exit, true)
              monitor.__send__(:mon_exit)
            else
              monitor.exit
            end
          end
        end

        Timeout.timeout(5) { acquired.pop }
        block.call
      ensure
        release << true if owner&.alive?
        assert Timeout.timeout(5) { owner.join } if owner
      end
    end

    test "creation attempts are balanced when public checkout and adapter creation fail" do
      pool = create_pool.call("pool-attempt-errors")
      pool.disconnect!

      pool.stub :new_connection, -> { raise "adapter creation failed" } do
        assert_raises(RuntimeError) { pool.checkout }
        assert_predicate pool, :tenant_pool_idle?, "public checkout must release its attempt after an adapter error"

        assert_raises(RuntimeError) { pool.send(:try_to_checkout_new_connection) }
        assert_predicate pool, :tenant_pool_idle?, "private adapter creation must release its attempt after an adapter error"
      end
    end

    test "retired pools reject public checkout and skip private maintenance checkout" do
      pool = create_pool.call("pool-stale-reference")
      pool.retire_tenant_pool!
      new_connection_calls = 0

      pool.stub :new_connection, -> { new_connection_calls += 1; raise "should not create an adapter" } do
        assert_raises(ActiveRecord::ConnectionNotEstablished) { pool.checkout }
        assert_nil pool.send(:try_to_checkout_new_connection)
        assert_equal 0, new_connection_calls
      end
    end

    test "pool is not idle while Rails is creating a connection or maintaining one" do
      pool = create_pool.call("pool-not-idle-maintenance")
      pool.disconnect!
      assert_predicate pool, :tenant_pool_idle?

      pool.synchronize { pool.instance_variable_set(:@now_connecting, 1) }
      assert_not pool.tenant_pool_idle?
      pool.synchronize { pool.instance_variable_set(:@now_connecting, 0) }

      connection = pool.checkout
      pool.checkin(connection)
      begin
        pool.send(:checkout_for_maintenance, connection)

        assert_not pool.tenant_pool_idle?
      ensure
        pool.send(:return_from_maintenance, connection)
      end

      assert_predicate pool, :tenant_pool_idle?
    end

    test "pool is not idle while a connection is checked out or pinned" do
      pool = create_pool.call("pool-not-idle-leased")

      connection = pool.checkout
      begin
        assert_not pool.tenant_pool_idle?
      ensure
        pool.checkin(connection)
      end

      pool.pin_connection!(false)
      begin
        assert_not pool.tenant_pool_idle?
      ensure
        pool.unpin_connection!
      end

      assert_predicate pool, :tenant_pool_idle?
    end

    test "a checked out connection owned by a dead thread still prevents retirement" do
      pool = create_pool.call("pool-dead-owner")
      leased = Queue.new
      owner = Thread.new do
        leased << pool.checkout
      end

      connection = Timeout.timeout(5) { leased.pop }
      assert Timeout.timeout(5) { owner.join }

      assert_predicate connection, :in_use?
      assert_not connection.owner.alive?
      assert_not pool.tenant_pool_idle?
    ensure
      owner&.kill if owner&.alive?
      owner&.join(5)
      pool&.reap
    end

    test "retirement checks out internally before marking the old pool stale and disconnects once" do
      root_config = TenantedApplicationRecord.tenanted_root_config
      tenant_a = "pool-retirement-a"
      tenant_b = "pool-retirement-b"
      internal_checkout_succeeded = false
      disconnect_count = 0

      root_config.stub :max_connection_pools, 1 do
        pool = create_pool.call(tenant_a)
        prepare_database.call(tenant_b)
        original_disconnect = pool.method(:disconnect!)
        pool.define_singleton_method(:disconnect!) do |*arguments, **options|
          disconnect_count += 1
          connection = checkout
          internal_checkout_succeeded = true
          checkin(connection)
          original_disconnect.call(*arguments, **options)
        end

        TenantedApplicationRecord.with_tenant(tenant_b) { User.count }

        assert internal_checkout_succeeded, "Rails disconnect must be allowed to check out before retirement completes"
        assert_equal 1, disconnect_count
        assert_predicate pool, :tenant_pool_retired?
        assert_raises(ActiveRecord::ConnectionNotEstablished) { pool.checkout }
        assert_nil pool.send(:try_to_checkout_new_connection)
      end
    end

    test "pool config, reaper, and main monitor contention skip an eviction promptly" do
      root_config = TenantedApplicationRecord.tenanted_root_config
      tenant_a = "pool-contention-a"
      tenant_b = "pool-contention-b"
      handler = TenantedApplicationRecord.connection_handler
      specification = TenantedApplicationRecord.connection_specification_name

      root_config.stub :max_connection_pools, 1 do
        pool = create_pool.call(tenant_a)
        prepare_database.call(tenant_b)
        monitors = [ pool.pool_config, pool.instance_variable_get(:@reaper_lock), pool ]

        monitors.each do |monitor|
          outcome = Queue.new
          requester = nil
          result = :blocked

          begin
            with_monitor_held_by_another_thread.call(monitor) do
              requester = Thread.new do
                TenantedApplicationRecord.with_tenant(tenant_b) { User.connection_pool }
                outcome << :created
              rescue StandardError => error
                outcome << error
              end

              begin
                result = Timeout.timeout(5) { outcome.pop }
              rescue Timeout::Error
                result = :blocked
              end
            end

            assert_not_equal :blocked, result, "eviction must skip a contended Rails monitor without waiting"
            assert_instance_of ActiveRecord::Tenanted::ConnectionPoolCapacityError, result
          ensure
            requester&.kill if requester&.alive?
            requester&.join(5)
          end

          assert_same pool, handler.retrieve_connection_pool(specification, role: :writing, shard: tenant_a, strict: false)
          assert_nil handler.retrieve_connection_pool(specification, role: :writing, shard: tenant_b, strict: false)
          registry_snapshot = TenantedApplicationRecord.tenanted_connection_pools.snapshot
          assert_equal [ [ tenant_a, :writing ] ], registry_snapshot.map(&:first)
          assert_same pool, registry_snapshot.first.last
        end
      end
    end

    test "an outstanding public checkout blocks retirement before Rails leases the adapter" do
      root_config = TenantedApplicationRecord.tenanted_root_config
      tenant_a = "pool-attempt-race-a"
      tenant_c = "pool-attempt-race-c"
      handler = TenantedApplicationRecord.connection_handler
      specification = TenantedApplicationRecord.connection_specification_name

      root_config.stub :max_connection_pools, 1 do
        pool = create_pool.call(tenant_a)
        prepare_database.call(tenant_c)
        checkout_started = Queue.new
        release_checkout = Queue.new
        checkout_result = Queue.new
        original_acquire_connection = pool.method(:acquire_connection)
        checkout_thread = nil
        capacity_thread = nil

        pool.stub :acquire_connection, ->(*arguments, **options) {
          checkout_started << true
          Timeout.timeout(5) { release_checkout.pop }
          original_acquire_connection.call(*arguments, **options)
        } do
          checkout_thread = Thread.new do
            connection = pool.checkout
            begin
              checkout_result << connection.select_value("SELECT 1")
            ensure
              pool.checkin(connection)
            end
          rescue StandardError => error
            checkout_result << error
          end

          begin
            Timeout.timeout(5) { checkout_started.pop }

            assert_not pool.tenant_pool_idle?
            assert_equal 0, pool.synchronize { pool.instance_variable_get(:@now_connecting) }

            capacity_result = Queue.new
            capacity_thread = Thread.new do
              TenantedApplicationRecord.with_tenant(tenant_c) { User.connection_pool }
              capacity_result << :created
            rescue StandardError => error
              capacity_result << error
            end

            capacity_error = Timeout.timeout(5) { capacity_result.pop }
            assert_instance_of ActiveRecord::Tenanted::ConnectionPoolCapacityError, capacity_error
            assert_same pool, handler.retrieve_connection_pool(
              specification, role: :writing, shard: tenant_a, strict: false
            )
            assert_nil handler.retrieve_connection_pool(
              specification, role: :writing, shard: tenant_c, strict: false
            )
          ensure
            release_checkout << true
            [ checkout_thread, capacity_thread ].compact.each do |thread|
              next unless thread.alive?

              thread.join(5)
              if thread.alive?
                thread.kill
                thread.join(5)
              end
            end
          end
        end

        assert_equal 1, Timeout.timeout(5) { checkout_result.pop }
      end
    end

    test "a stale checkout waits for eviction disconnect before seeing retirement" do
      root_config = TenantedApplicationRecord.tenanted_root_config
      tenant_a = "pool-stale-race-a"
      tenant_c = "pool-stale-race-c"
      disconnect_started = Queue.new
      release_disconnect = Queue.new
      internal_checkout_succeeded = false
      stale_checkout_started = Queue.new
      stale_result = Queue.new
      creation_result = Queue.new
      creator = nil
      stale_checkout = nil
      stale_checkout_thread = nil

      root_config.stub :max_connection_pools, 1 do
        pool = create_pool.call(tenant_a)
        prepare_database.call(tenant_c)
        handler = TenantedApplicationRecord.connection_handler
        specification = TenantedApplicationRecord.connection_specification_name
        original_disconnect = pool.method(:disconnect!)
        original_attempt = pool.method(:with_tenant_checkout_attempt)

        pool.define_singleton_method(:with_tenant_checkout_attempt) do |stale: :raise, &block|
          stale_checkout_started << true if Thread.current.equal?(stale_checkout_thread)
          original_attempt.call(stale: stale, &block)
        end

        pool.define_singleton_method(:disconnect!) do |*arguments, **options|
          connection = checkout
          internal_checkout_succeeded = true
          checkin(connection)
          disconnect_started << true
          Timeout.timeout(5) { release_disconnect.pop }
          original_disconnect.call(*arguments, **options)
        end

        creator = Thread.new do
          TenantedApplicationRecord.with_tenant(tenant_c) { User.count }
          creation_result << :created
        rescue StandardError => error
          creation_result << error
        end

        begin
          Timeout.timeout(5) { disconnect_started.pop }
          assert internal_checkout_succeeded, "Rails disconnect must still be able to check out internally"
          assert_nil handler.retrieve_connection_pool(specification, role: :writing, shard: tenant_a, strict: false)

          stale_checkout = Thread.new do
            stale_checkout_thread = Thread.current
            connection = pool.checkout
            pool.checkin(connection)
            stale_result << :leased
          rescue StandardError => error
            stale_result << error
          end

          Timeout.timeout(5) { stale_checkout_started.pop }
          release_disconnect << true

          creation = Timeout.timeout(5) { creation_result.pop }
          stale = Timeout.timeout(5) { stale_result.pop }

          assert_equal :created, creation
          assert_instance_of ActiveRecord::ConnectionNotEstablished, stale
          assert_predicate pool, :tenant_pool_retired?
          assert_nil handler.retrieve_connection_pool(specification, role: :writing, shard: tenant_a, strict: false)
          assert_not_nil handler.retrieve_connection_pool(specification, role: :writing, shard: tenant_c, strict: false)
        ensure
          release_disconnect << true
          [ creator, stale_checkout ].compact.each do |thread|
            next unless thread.alive?

            thread.join(5)
            if thread.alive?
              thread.kill
              thread.join(5)
            end
          end
        end
      end
    end

    test "adapter connections on one pool can be created concurrently" do
      pool = create_pool.call("pool-parallel-adapters")
      pool.disconnect!
      arrivals = Queue.new
      release = Queue.new
      errors = Queue.new
      original_checkout_new_connection = pool.method(:checkout_new_connection)
      workers = []
      arrivals_count = 0

      pool.stub :checkout_new_connection, -> { arrivals << true; Timeout.timeout(5) { release.pop }; original_checkout_new_connection.call } do
        workers = 2.times.map do
          Thread.new do
            connection = pool.checkout
            pool.checkin(connection)
          rescue StandardError => error
            errors << error
          end
        end

        begin
          2.times do
            Timeout.timeout(5) { arrivals.pop }
            arrivals_count += 1
          end
          assert_not pool.tenant_pool_idle?, "active adapter creation must prevent the pool from being retired"
        rescue Timeout::Error
          # Release any connection attempt that arrived so workers can finish.
        end
      ensure
        2.times { release << true }
        workers.each do |worker|
          next unless worker&.alive?

          finished = worker.join(5)
          unless finished
            worker.kill
            worker.join(5)
          end
        end
      end

      assert_equal 2, arrivals_count, "both adapter creations should reach the barrier before either continues"
      assert_empty errors
      assert_equal 2, pool.connections.size
    end
  end
end

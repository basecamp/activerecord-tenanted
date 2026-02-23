# frozen_string_literal: true

module ActiveRecord
  module Tenanted
    # MySQL adapter extension that makes shared pool connections tenant-aware.
    #
    # This module handles two lifecycle seams:
    #
    # 1. Checkout: switch the connection to the current tenant's database via
    #    USE and attach a tenant-namespaced query cache.
    # 2. Checkin: reset the connection to the fallback database.
    #
    # This is Layer 1 of the dual-layer safety model. It covers first checkouts
    # and connection teardown. Layer 2 (tenant context reconciliation in Tenant)
    # covers sticky leases and nested with_tenant.
    #
    # Included into Mysql2Adapter and TrilogyAdapter via Railtie load hooks.
    # All methods guard on shared_pool? so non-shared-pool connections see a
    # single hash lookup and early return.
    module SharedPool
      extend ActiveSupport::Concern

      included do
        attr_accessor :tenant_database

        set_callback :checkout, :after, :apply_current_tenant
        set_callback :checkin, :after, :reset_to_fallback
      end

      def apply_current_tenant
        return unless shared_pool?

        attach_query_cache_namespace

        klass = tenanted_connection_class
        tenant = klass.current_tenant

        if tenant.blank?
          raise TenantSwitchError,
            "Cannot switch tenant database during checkout because no tenant " \
            "context is set (connection class #{klass.name.inspect})."
        end

        database = klass.tenanted_root_config.database_for(tenant)
        switch_tenant_database(tenant: tenant.to_s, database: database)
      end

      def reset_to_fallback
        return unless shared_pool?

        db = @config[:untenanted_database]
        internal_execute("USE #{quote_table_name(db)}", "TENANT RESET", allow_retry: false)

        self.tenant = nil
        self.tenant_database = db
      rescue => error
        throw_away!
        raise TenantResetError,
          "Failed to reset connection to fallback database #{db.inspect} " \
          "from tenant #{tenant.inspect}: #{error.class}: #{error.message}"
      end

      # Override the query_cache getter to ensure tenant namespace isolation
      # on Rails' pinned cross-thread path. When a connection is pinned
      # (transactional fixtures, system tests) and accessed from a non-owner
      # thread, Rails returns pool.query_cache directly, bypassing the
      # NamespaceStore wrapper set during checkout. This re-wraps it so
      # cache keys remain namespaced by tenant database.
      def query_cache
        cache = super
        if cache && shared_pool? && !cache.is_a?(NamespaceStore)
          NamespaceStore.new(cache, -> { tenant_database || @config[:untenanted_database] })
        else
          cache
        end
      end

      def switch_tenant_database(tenant:, database:)
        return if self.tenant == tenant && tenant_database == database

        if transaction_open?
          raise TenantSwitchInTransactionError,
            "Cannot switch to tenant #{tenant.inspect} (database #{database.inspect}) " \
            "because a transaction is open."
        end

        internal_execute("USE #{quote_table_name(database)}", "TENANT SWITCH", allow_retry: false)

        self.tenant = tenant
        self.tenant_database = database
      rescue TenantSwitchInTransactionError
        raise
      rescue => error
        throw_away!
        raise TenantSwitchError,
          "Failed to switch to tenant #{tenant.inspect} " \
          "(database #{database.inspect}): #{error.class}: #{error.message}"
      end

      private
        def shared_pool?
          @config[:shared_pool] == true && @config.key?(:tenanted_connection_class_name)
        end

        def tenanted_connection_class
          @config.fetch(:tenanted_connection_class_name).constantize
        end

        def attach_query_cache_namespace
          self.query_cache = NamespaceStore.new(
            pool.query_cache,
            -> { tenant_database || @config[:untenanted_database] }
          )
        end

        # Thin wrapper that prefixes query cache keys with the current tenant
        # database name. Prevents cross-tenant cache hits when two tenants
        # execute the same SQL on the same connection within one request.
        class NamespaceStore
          delegate :enabled, :enabled=, :enabled?, :dirties, :dirties=, :dirties?,
                   :clear, :size, :empty?, to: :base_store

          attr_reader :base_store

          def initialize(base_store, namespace_proc)
            @base_store = base_store
            @namespace_proc = namespace_proc
          end

          def [](key)
            base_store[namespaced(key)]
          end

          def compute_if_absent(key, &block)
            base_store.compute_if_absent(namespaced(key), &block)
          end

          private
            def namespaced(key)
              [@namespace_proc.call, key]
            end
        end
    end
  end
end

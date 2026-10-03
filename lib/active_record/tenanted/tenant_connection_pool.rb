# frozen_string_literal: true

module ActiveRecord
  module Tenanted
    class TenantConnectionPool < ActiveRecord::ConnectionAdapters::ConnectionPool # :nodoc:
      def initialize(...)
        @tenant_checkout_attempts = 0
        @tenant_pool_retired = false
        @tenant_pool_failed = false
        @tenant_pool_owner = ActiveSupport::IsolatedExecutionState.context if ActiveSupport::IsolatedExecutionState[:active_record_tenanted_provisional_pool]
        @tenant_pool_ready = @tenant_pool_owner.nil?
        super
      end

      def checkout(...)
        with_tenant_checkout_attempt { super }
      end

      def try_with_retirement_barriers
        return false unless @reaper_lock.try_enter

        begin
          return false unless mon_try_enter

          begin
            yield
          ensure
            mon_exit
          end
        ensure
          @reaper_lock.exit
        end
      end

      def tenant_pool_idle?
        synchronize do
          !@tenant_pool_retired &&
            @tenant_checkout_attempts.zero? &&
            @now_connecting.zero? &&
            @maintaining.zero? &&
            @pinned_connection.nil? &&
            @connections.none?(&:in_use?)
        end
      end

      def retire_tenant_pool!
        synchronize { @tenant_pool_retired = true }
      end

      def tenant_pool_ready?
        @tenant_pool_ready
      end

      def tenant_pool_available_to_current_context?
        !@tenant_pool_failed && !@tenant_pool_retired &&
          (@tenant_pool_ready || @tenant_pool_owner.equal?(ActiveSupport::IsolatedExecutionState.context))
      end

      def tenant_pool_ready!
        synchronize do
          @tenant_pool_ready = true
          @tenant_pool_owner = nil
        end
      end

      def tenant_pool_failed!
        @tenant_pool_failed = true
        @tenant_pool_owner = nil
      end

      def tenant_pool_retired?
        @tenant_pool_retired
      end

      def tenant_pool_failed?
        @tenant_pool_failed
      end

      private
        def try_to_checkout_new_connection(...)
          with_tenant_checkout_attempt(stale: :skip) { super }
        end

        def with_tenant_checkout_attempt(stale: :raise)
          admitted = synchronize do
            if @tenant_pool_retired || @tenant_pool_failed ||
                (!@tenant_pool_ready && !@tenant_pool_owner.equal?(ActiveSupport::IsolatedExecutionState.context))
              false
            else
              @tenant_checkout_attempts += 1
              true
            end
          end

          unless admitted
            return if stale == :skip

            raise ActiveRecord::ConnectionNotEstablished, "tenant connection pool is not available"
          end

          begin
            yield
          ensure
            synchronize { @tenant_checkout_attempts -= 1 }
          end
        end
    end
  end
end

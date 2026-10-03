# frozen_string_literal: true

module ActiveRecord
  module Tenanted
    # Inspired by the lru_redux gem, this LRU queue relies on Concurrent::Hash being ordered
    class LRU # :nodoc:
      def initialize
        @data = Concurrent::Hash.new
      end

      def [](key)
        found = true
        value = @data.delete(key) { found = false }
        if found
          @data[key] = value
        else
          nil
        end
      end

      def peek(key)
        @data[key]
      end

      def []=(key, value)
        @data.delete key
        @data[key] = value
        value
      end

      def size
        @data.size
      end

      def pop
        key, value = @data.first
        @data.delete(key)
        [ key, value ]
      end

      def snapshot
        @data.to_a
      end

      def delete_if_same(key, value)
        return false unless @data[key].equal?(value)

        @data.delete(key)
        true
      end

      def keys
        @data.keys
      end
    end

    Lru = LRU
  end
end

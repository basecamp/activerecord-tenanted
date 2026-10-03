# frozen_string_literal: true

require "test_helper"

describe ActiveRecord::Tenanted::LRU do
  let(:lru) { ActiveRecord::Tenanted::LRU.new }

  it "stores and retrieves values" do
    assert_equal 0, lru.size

    lru[:a] = 1

    assert_equal 1, lru.size

    lru[:b] = 2

    assert_equal 2, lru.size

    lru[:c] = 3

    assert_equal 3, lru.size
    assert_equal 1, lru[:a]
    assert_equal 2, lru[:b]
    assert_equal 3, lru[:c]

    lru[:b] = 12

    assert_equal 3, lru.size
    assert_equal 1, lru[:a]
    assert_equal 12, lru[:b]
    assert_equal 3, lru[:c]
  end

  it "moves written keys to the end" do
    lru[:a] = 1
    lru[:b] = 2
    lru[:c] = 3

    assert_equal [ :a, :b, :c ], lru.keys

    lru[:b] = 12

    assert_equal [ :a, :c, :b ], lru.keys

    lru[:a] = 11

    assert_equal 3, lru.size
    assert_equal [ :c, :b, :a ], lru.keys
  end

  it "moves read keys to the end" do
    lru[:a] = 1
    lru[:b] = 2
    lru[:c] = 3

    assert_equal [ :a, :b, :c ], lru.keys

    lru[:b]

    assert_equal [ :a, :c, :b ], lru.keys

    lru[:a]

    assert_equal [ :c, :b, :a ], lru.keys
  end

  it "pops the oldest key" do
    lru[:a] = 1
    lru[:b] = 2
    lru[:c] = 3

    assert_equal [ :a, :b, :c ], lru.keys

    key, value = lru.pop

    assert_equal :a, key
    assert_equal 1, value
    assert_equal 2, lru.size
    assert_equal [ :b, :c ], lru.keys

    key, value = lru.pop

    assert_equal :b, key
    assert_equal 2, value
    assert_equal 1, lru.size
    assert_equal [ :c ], lru.keys

    key, value = lru.pop

    assert_equal :c, key
    assert_equal 3, value
    assert_equal 0, lru.size
    assert_equal [], lru.keys

    key, value = lru.pop

    assert_nil key
    assert_nil value
    assert_equal 0, lru.size
    assert_equal [], lru.keys
  end

  test "peek reads a value without changing oldest-first order" do
    oldest = Object.new
    newest = Object.new
    lru[:oldest] = oldest
    lru[:newest] = newest

    assert_same oldest, lru.peek(:oldest)
    assert_equal [ :oldest, :newest ], lru.snapshot.map(&:first)
    assert_equal [ :oldest, :newest ], lru.keys
  end

  test "snapshot preserves oldest-first entries and is a copy" do
    lru[:first] = Object.new
    lru[:second] = Object.new

    snapshot = lru.snapshot
    lru[:third] = Object.new

    assert_equal [ :first, :second ], snapshot.map(&:first)
    assert_equal 2, snapshot.length
  end

  test "conditional delete leaves a replacement value in place" do
    previous = Object.new
    replacement = Object.new
    lru[:tenant] = previous
    lru[:tenant] = replacement

    assert_not lru.delete_if_same(:tenant, previous)
    assert_same replacement, lru.peek(:tenant)
    assert_equal [ :tenant ], lru.keys
  end

  test "conditional delete removes only the matching value" do
    value = Object.new
    lru[:tenant] = value

    assert lru.delete_if_same(:tenant, value)
    assert_nil lru.peek(:tenant)
    assert_empty lru.keys
  end
end

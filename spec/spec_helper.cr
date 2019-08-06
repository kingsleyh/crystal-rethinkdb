require "spec"
require "../src/crystal-rethinkdb"
include RethinkDB::Shortcuts

module Generators
  @@i = 0

  private def self.i
    @@i = @@i + 1
  end

  def self.random_table
    "test_#{Time.utc.to_unix}_#{rand(10000)}_#{i}"
  end

  def self.random_table
    yield random_table
  end

  def self.random_pk
    "pk_#{Time.utc.to_unix}_#{rand(100)}_#{i}"
  end

  def self.random_pk
    yield random_pk
  end

  def self.random_array(length = 5)
    length.times.map { |_| rand(100) }.to_a
  end

  def self.random_hash(num_keys = 4)
    num_keys.times.map { |_| ({self.random_pk, rand(100)}) }.to_h
  end

  def self.random_table_with_entries(num_entries : Int32, block)
    Generators.random_table do |table|
      r.table_create(table).run(Fixtures::TestDB.conn)
      num_entries.times do
        document = {
          "id"     => Generators.random_pk,
          "serial" => Generators.random_pk,
          "array"  => Generators.random_array,
          "object" => Generators.random_hash,
        }
        response = r.json(document.to_json).do { |value|
          r.table(table).insert(value, return_changes: true)
        }.run(Fixtures::TestDB.conn)
      end
      begin
        block.call(table)
      ensure
        r.table_drop(table).run Fixtures::TestDB.conn
      end
    end
  end

end

module Fixtures
  class TestDB
    @@host = uninitialized String

    begin
      r.connect({host: "rethinkdb"}).close
      @@host = "rethinkdb"
    rescue
    end

    begin
      r.connect({host: "localhost"}).close
      @@host = "localhost"
    rescue
    end

    if @@host
      puts "Identified RethinkDB at tcp://#{@@host}"
    else
      STDERR.puts "Unable to identify running instance of RethinkDB. Run it at 'localhost' or 'rethinkdb'."
      exit
    end

    def self.host
      @@host
    end

    def self.conn
      r.connect({host: host})
    end
  end
end

# ReQL matchers
###################

def match_reql_output(result)
  result = result.to_a if result.is_a? RethinkDB::Cursor
  matcher = with ReqlMatchers.new yield
  recursive_match result, matcher
end

def recursive_match(result, target)
  case target
  when Matcher
    target.match(result)
  when Array
    result.raw.should be_a Array(RethinkDB::QueryResult)
    result.size.should eq target.size
    result.size.times do |i|
      recursive_match result[i], target[i]
    end
  when Hash
    result.raw.should be_a Hash(String, RethinkDB::QueryResult)
    (result.keys - result.keys).size.should eq 0
    result.keys.each do |key|
      recursive_match result[key], target[key]
    end
  else
    result.should eq target
  end
end

def recursive_match(result : Array, target)
  result.should be_a Array(RethinkDB::QueryResult)
  result.size.should eq target.size
  result.size.times do |i|
    recursive_match result[i], target[i]
  end
end

struct ReqlMatchers
  def int_cmp(value)
    IntCmpMatcher.new(value.to_i64)
  end

  def float_cmp(value)
    FloatCmpMatcher.new(value.to_f64)
  end

  def uuid
    UUIDMatcher.new
  end

  def arrlen(len, matcher)
    ArrayMatcher.new(len, matcher)
  end

  def partial(matcher)
    PartialMatcher.new(matcher)
  end
end

abstract struct Matcher
end

struct IntCmpMatcher < Matcher
  def initialize(@value : Int64)
  end

  def match(result)
    result.should eq @value
    result.raw.should be_a Int64
  end
end

struct FloatCmpMatcher < Matcher
  def initialize(@value : Float64)
  end

  def match(result)
    result.should eq @value
    result.raw.should be_a Float64
  end
end

struct UUIDMatcher < Matcher
  def match(result)
    result.raw.should be_a String
    result.as_s.should Spec::MatchExpectation.new(/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i)
  end
end

struct ArrayMatcher(T) < Matcher
  def initialize(@size : Int32, @matcher : T)
  end

  def match(result)
    result.raw.should be_a Array(RethinkDB::QueryResult)
    result.size.should eq @size
    result.as_a.each do |value|
      recursive_match value, @matcher
    end
  end
end

struct PartialMatcher(T) < Matcher
  def initialize(@object : Hash(String, T))
  end

  def match(result)
    result.raw.should be_a Hash(String, RethinkDB::QueryResult)
    @object.keys.each do |key|
      result.keys.includes?(key).should be_true
      recursive_match result[key], @object[key]
    end
  end
end

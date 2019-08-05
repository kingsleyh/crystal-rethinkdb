require "json"
require "./term"
require "uuid"

alias ReqlType = Nil | Bool | Int64 | Float64 | String | UUID | Array(ReqlType) | Hash(String, ReqlType)

class Array(T)
  def to_reql
    JSON.parse([
      RethinkDB::TermType::MAKE_ARRAY.to_i64,
      map { |x| x.to_reql },
    ].to_json)
  end
end

struct Tuple
  def to_reql
    JSON.parse([
      RethinkDB::TermType::MAKE_ARRAY.to_i64,
      to_a.map { |x| x.to_reql },
    ].to_json)
  end
end

struct UUID
  def to_reql
    to_s.to_reql
  end
end

class Hash(K, V)
  def to_reql
    hash = {} of String => JSON::Any
    each do |k, v|
      hash[k.to_s] = v.to_reql
    end
    JSON.parse(hash.to_json)
  end
end

struct NamedTuple
  def to_reql
    hash = {} of String => JSON::Any
    each do |k, v|
      hash[k.to_s] = v.to_reql
    end
    JSON.parse(hash.to_json)
  end
end

struct Nil
  def to_reql
    JSON.parse(self.to_json)
  end
end

struct Int
  def to_reql
    JSON.parse(to_i64.to_json)
  end
end

struct Float
  def to_reql
    JSON.parse(to_f64.to_json)
  end
end

class String
  def to_reql
    JSON.parse(self.to_json)
  end
end

struct Symbol
  def to_reql
    JSON.parse(to_s.to_json)
  end
end

struct Bool
  def to_reql
    JSON.parse(self.to_json)
  end
end

struct Time
  def to_reql
    JSON.parse({"$reql_type$" => "TIME", "timezone" => "+00:00", "epoch_time" => to_utc.to_unix}.to_json)
  end

  struct Span
    def to_reql
      JSON.parse(to_i.to_i64.to_json)
    end
  end
end

module RethinkDB
  struct QueryResult
    alias Type = Nil | Bool | Int64 | Float64 | String | Time | Array(QueryResult) | Hash(String, QueryResult)
    property raw : Type

    def self.new(pull : JSON::PullParser)
      case pull.kind
      when .null?
        new pull.read_null
      when .bool?
        new pull.read_bool
      when .int?
        new pull.read_int
      when .float?
        new pull.read_float
      when .string?
        new pull.read_string
      when .begin_array?
        ary = [] of QueryResult
        pull.read_array do
          ary << new(pull)
        end
        new ary
      when .begin_object?
        hash = {} of String => QueryResult
        pull.read_object do |key|
          hash[key] = new(pull)
        end
        new hash
      else
        raise "Unknown pull kind: #{pull.kind}"
      end
    end

    def initialize(@raw : Type)
    end

    # Converts following ReQL formats
    # - TIME
    # - GROUP
    # - BINARY
    def self.transformed(obj : QueryResult, time_format : String, group_format : String, binary_format : String) : QueryResult
      case (raw = obj.raw)
      when Array
        QueryResult.new obj.as_a.map { |x| QueryResult.transformed(x, time_format, group_format, binary_format) }
      when Hash
        reql_type = obj["$reql_type$"]?

        if reql_type == "TIME" && time_format == "native"
          epoch = (obj["epoch_time"].as_f? || obj["epoch_time"].as_i).to_i
          time = Time.unix(epoch)

          match = (obj["timezone"].as_s).match(/([+-]\d\d):(\d\d)/).not_nil!
          time += match[1].to_i.hours
          time += match[2].to_i.minutes

          return QueryResult.new(time.as Type)
        end

        if reql_type == "GROUPED_DATA" && group_format == "native"
          grouped = obj["data"].as_a.map do |data|
            group, reduction = data.as_a[0..1]
            QueryResult.new({"group" => group, "reduction" => reduction})
          end

          return QueryResult.transformed(QueryResult.new(grouped), time_format, group_format, binary_format)
        end

        transform = raw.transform_values { |v| QueryResult.transformed(v, time_format, group_format, binary_format) }
        QueryResult.new(transform)
      else
        obj
      end
    end

    def transformed(time_format, group_format, binary_format)
      QueryResult.transformed(self, time_format, group_format, binary_format)
    end

    def size : Int
      case (object = @raw)
      when Array
        object.size
      when Hash
        object.size
      else
        raise "expected Array or Hash for #size, not #{object.class}"
      end
    end

    def keys
      case (object = @raw)
      when Hash
        object.keys
      else
        raise "expected Hash for #keys, not #{object.class}"
      end
    end

    def [](index : Int) : QueryResult
      case (object = @raw)
      when Array
        object[index]
      else
        raise "expected Array for #[](index : Int), not #{object.class}"
      end
    end

    def []?(index : Int) : QueryResult?
      case (object = @raw)
      when Array
        object[index]?
      else
        raise "expected Array for #[]?(index : Int), not #{object.class}"
      end
    end

    def [](key : String) : QueryResult
      case (object = @raw)
      when Hash
        object[key]
      else
        raise "expected Hash for #[](key : String), not #{object.class}"
      end
    end

    def []?(key : String) : QueryResult?
      case (object = @raw)
      when Hash
        object[key]?
      else
        raise "expected Hash for #[]?(key : String), not #{object.class}"
      end
    end

    def inspect(io)
      raw.inspect(io)
    end

    # :nodoc:
    def to_json(json : JSON::Builder)
      raw.to_json(json)
    end

    # :nodoc:
    def to_yaml(yaml : YAML::Nodes::Builder)
      raw.to_yaml(yaml)
    end

    # Returns a new QueryResult instance with the `raw` value `dup`ed.
    def dup
      QueryResult.new(raw.dup)
    end

    # Returns a new QueryResult instance with the `raw` value `clone`ed.
    def clone
      QueryResult.new(raw.clone)
    end

    def to_s(io)
      raw.to_s(io)
    end

    def ==(other : QueryResult)
      raw == other.raw
    end

    def ==(other)
      raw == other
    end

    def_hash raw

    def as_nil : Nil
      @raw.as(Nil)
    end

    def as_bool : Bool
      @raw.as(Bool)
    end

    def as_bool? : Bool?
      as_bool if @raw.is_a?(Bool)
    end

    def as_i : Int32
      @raw.as(Int).to_i
    end

    def as_i? : Int32?
      as_i if @raw.is_a?(Int)
    end

    def as_i64 : Int64
      @raw.as(Int).to_i64
    end

    def as_i64? : Int64?
      as_i64 if @raw.is_a?(Int64)
    end

    def as_f : Float64
      @raw.as(Float).to_f
    end

    def as_f? : Float64?
      as_f if @raw.is_a?(Float64)
    end

    def as_f32 : Float32
      @raw.as(Float).to_f32
    end

    def as_f32? : Float32?
      as_f32 if (@raw.is_a?(Float32) || @raw.is_a?(Float64))
    end

    def as_s : String
      @raw.as(String)
    end

    def as_s? : String?
      as_s if @raw.is_a?(String)
    end

    def as_a : Array(QueryResult)
      @raw.as(Array)
    end

    def as_a? : Array(QueryResult)?
      as_a if @raw.is_a?(Array)
    end

    def as_h : Hash(String, QueryResult)
      @raw.as(Hash)
    end

    def as_h? : Hash(String, QueryResult)?
      as_h if @raw.is_a?(Hash)
    end

    def as_time : Time
      @raw.as(Time)
    end

    def as_time? : Time?
      as_time if @raw.is_a?(Time)
    end

    def to_reql
      @raw.to_reql
    end
  end
end

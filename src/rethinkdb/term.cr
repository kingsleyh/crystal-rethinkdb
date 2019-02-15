require "json"

module RethinkDB
  class Term
    @reql : JSON::Any

    def initialize(any : JSON::Any)
      @reql = JSON.parse(any.to_json)
    end

    def initialize(type : RethinkDB::TermType)
      @reql = JSON.parse([type.to_i64].to_json)
    end

    def initialize(type : RethinkDB::TermType, args : Array)
      args = args.map(&.to_reql.as(JSON::Any))
      @reql = JSON.parse([
        type.to_i64,
        args,
      ].to_json)
    end

    def initialize(type : RethinkDB::TermType, args : Array, options)
      args = args.map(&.to_reql.as(JSON::Any))
      @reql = JSON.parse([
        type.to_i64,
        args,
        options.to_reql,
      ].to_json)
    end

    def to_reql
      @reql
    end

    def clone
      self.class.new(@reql.clone)
    end
  end

  class Func < Term
    @@vars = 0

    def self.arity0
      super(TermType::FUNC, [[] of Int64, yield])
    end

    def self.arity1
      vars = {1}.map { @@vars += 1 }
      args = vars.map { |v| DatumTerm.new(TermType::VAR, [v]) }
      result = yield(args[0])
      Term.new(TermType::FUNC, [vars.to_a, result])
    end

    def self.arity2
      vars = {1, 2}.map { @@vars += 1 }
      args = vars.map { |v| DatumTerm.new(TermType::VAR, [v]) }
      result = yield(args[0], args[1])
      Term.new(TermType::FUNC, [vars.to_a, result])
    end

    def self.arity3
      vars = {1, 2, 3}.map { @@vars += 1 }
      args = vars.map { |v| DatumTerm.new(TermType::VAR, [v]) }
      result = yield(args[0], args[1], args[2])
      Term.new(TermType::FUNC, [vars.to_a, result])
    end

    def self.arity4
      vars = {1, 2, 3, 4}.map { @@vars += 1 }
      args = vars.map { |v| DatumTerm.new(TermType::VAR, [v]) }
      result = yield(args[0], args[1], args[2], args[3])
      Term.new(TermType::FUNC, [vars.to_a, result])
    end

    def self.arity5
      vars = {1, 2, 3, 4, 5}.map { @@vars += 1 }
      args = vars.map { |v| DatumTerm.new(TermType::VAR, [v]) }
      result = yield(args[0], args[1], args[2], args[3], args[4])
      Term.new(TermType::FUNC, [vars.to_a, result])
    end
  end

  class ErrorTerm < Term
    def run(conn, **runopts)
      conn.query_error(self, runopts)
    end

    def run(conn)
      conn.query_error(self, {} of String => String)
    end

    def run(conn, runopts : Hash | NamedTuple)
      conn.query_error(self, runopts)
    end
  end

  class DatumTerm < Term
    def run(conn, **runopts)
      conn.query_datum(self, runopts)
    end

    def run(conn)
      conn.query_datum(self, {} of String => String)
    end

    def run(conn, runopts : Hash | NamedTuple)
      conn.query_datum(self, runopts)
    end
  end

  class StreamTerm < Term
    def run(conn, **runopts)
      conn.query_cursor(self, runopts)
    end

    def run(conn)
      conn.query_cursor(self, {} of String => String)
    end

    def run(conn, runopts : Hash | NamedTuple)
      conn.query_cursor(self, runopts)
    end
  end

  class ChangesTerm < Term
    def run(conn, **runopts) : Cursor
      conn.query_changefeed(self, **runopts)
    end

    def run(conn) : Cursor
      conn.query_changefeed(self, {} of String => String)
    end
  end
end

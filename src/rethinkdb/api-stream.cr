require "./term"

module RethinkDB
  class StreamTerm
    def count
      DatumTerm.new(TermType::COUNT, [self])
    end

    def count
      DatumTerm.new(TermType::COUNT, [self, Func.arity1 { |row| yield(row) }])
    end

    def default(value)
      DatumTerm.new(TermType::DEFAULT, [self, value])
    end

    def default
      DatumTerm.new(TermType::DEFAULT, [self, Func.arity1 { |row| yield(row) }])
    end

    def do(*args)
      r.do(self, *args)
    end

    def do(*args)
      r.do(self, *args) { |a, b, c, d, e| yield(a, b, c, d, e) }
    end

    def limit(n)
      StreamTerm.new(TermType::LIMIT, [self, n])
    end

    def zip
      StreamTerm.new(TermType::ZIP, [self])
    end

    def [](key)
      StreamTerm.new(TermType::BRACKET, [self, key])
    end

    def filter(callable)
      StreamTerm.new(TermType::FILTER, [self, callable])
    end

    def filter
      StreamTerm.new(TermType::FILTER, [self, Func.arity1 { |row| yield(row) }])
    end

    def filter(**kargs)
      StreamTerm.new(TermType::FILTER, [self, Func.arity1 { |row| yield(row) }], kargs)
    end

    def pluck(*args)
      StreamTerm.new(TermType::PLUCK, [self] + args.to_a)
    end

    def eq_join(table, callable)
      StreamTerm.new(TermType::EQ_JOIN, [self, table, callable])
    end

    def concat_map(callable)
      StreamTerm.new(TermType::CONCAT_MAP, [self, callable])
    end

    def concat_map
      StreamTerm.new(TermType::CONCAT_MAP, [self, Func.arity1 { |row| yield(row) }])
    end

    def map(callable)
      StreamTerm.new(TermType::MAP, [self, callable])
    end

    def map
      StreamTerm.new(TermType::MAP, [self, Func.arity1 { |row| yield(row) }])
    end

    def for_each(callable)
      DatumTerm.new(TermType::FOR_EACH, [self, callable])
    end

    def for_each
      DatumTerm.new(TermType::FOR_EACH, [self, Func.arity1 { |row| yield(row) }])
    end

    def order_by
      DatumTerm.new(TermType::ORDER_BY, [self, Func.arity1 { |row| yield(row) }])
    end

    def order_by(**kargs)
      StreamTerm.new(TermType::ORDER_BY, [self], kargs.to_h)
    end

    def order_by(options : Hash | NamedTuple)
      StreamTerm.new(TermType::ORDER_BY, [self], options)
    end

    def order_by(callable)
      DatumTerm.new(TermType::ORDER_BY, [self, callable])
    end

    def sum
      DatumTerm.new(TermType::SUM, [self])
    end

    def sum
      DatumTerm.new(TermType::SUM, [self, Func.arity1 { |row| yield(row) }])
    end

    def sum(field)
      DatumTerm.new(TermType::SUM, [self, field])
    end

    def avg
      DatumTerm.new(TermType::AVG, [self])
    end

    def avg
      DatumTerm.new(TermType::AVG, [self, Func.arity1 { |row| yield(row) }])
    end

    def avg(field)
      DatumTerm.new(TermType::AVG, [self, field])
    end

    def min
      DatumTerm.new(TermType::MIN, [self])
    end

    def min
      DatumTerm.new(TermType::MIN, [self, Func.arity1 { |row| yield(row) }])
    end

    def min(field)
      DatumTerm.new(TermType::MIN, [self, field])
    end

    def min(**options)
      DatumTerm.new(TermType::MIN, [self], options)
    end

    def max
      DatumTerm.new(TermType::MAX, [self])
    end

    def max
      DatumTerm.new(TermType::MAX, [self, Func.arity1 { |row| yield(row) }])
    end

    def max(field)
      DatumTerm.new(TermType::MAX, [self, field])
    end

    def max(**options)
      DatumTerm.new(TermType::MAX, [self], options)
    end

    def group(**options)
      GroupedStreamTerm.new(TermType::GROUP, [self], options)
    end

    def group(*fields, **options)
      GroupedStreamTerm.new(TermType::GROUP, [self] + fields.to_a, options)
    end

    def group
      GroupedStreamTerm.new(TermType::GROUP, [self, Func.arity1 { |row| yield(row) }])
    end

    def reduce(callable)
      StreamTerm.new(TermType::REDUCE, [self, callable])
    end

    def reduce
      StreamTerm.new(TermType::REDUCE, [self, Func.arity2 { |a, b| yield(a, b) }])
    end

    def union(other)
      StreamTerm.new(TermType::UNION, [self, other])
    end

    def distinct(**kargs)
      StreamTerm.new(TermType::DISTINCT, [self], kargs)
    end

    def distinct(options : Hash | NamedTuple)
      StreamTerm.new(TermType::DISTINCT, [self], options)
    end

    def between(a, b, options : Hash | NamedTuple)
      StreamTerm.new(TermType::BETWEEN, [self, a, b], options)
    end

    def between(a, b, **kargs)
      StreamTerm.new(TermType::BETWEEN, [self, a, b], kargs)
    end

    def without(*fields)
      StreamTerm.new(TermType::WITHOUT, [self] + fields.to_a)
    end
  end
end

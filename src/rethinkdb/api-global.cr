require "./term"

module RethinkDB
  def self.db(name)
    DBTerm.new(TermType::DB, [name])
  end

  def self.db_list
    DatumTerm.new(TermType::DB_LIST)
  end

  def self.db_drop(name)
    DatumTerm.new(TermType::DB_DROP, [name])
  end

  def self.db_create(name)
    DatumTerm.new(TermType::DB_CREATE, [name])
  end

  def self.expr(any)
    DatumTerm.new(any.to_reql)
  end

  def self.now
    DatumTerm.new(TermType::NOW)
  end

  def self.minval
    DatumTerm.new(TermType::MINVAL)
  end

  def self.maxval
    DatumTerm.new(TermType::MAXVAL)
  end

  def self.range
    StreamTerm.new(TermType::RANGE)
  end

  def self.range(a)
    StreamTerm.new(TermType::RANGE, [a])
  end

  def self.range(a, b)
    StreamTerm.new(TermType::RANGE, [a, b])
  end

  def self.range(a, b, step)
    StreamTerm.new(TermType::RANGE, [a, b, step])
  end

  def self.do
    DatumTerm.new(TermType::FUNCALL)
  end

  def self.do(*args)
    args = args.to_a
    DatumTerm.new(TermType::FUNCALL, [args.pop] + args)
  end

  def self.do(*args)
    args = args + {nil, nil, nil, nil, nil}
    DatumTerm.new(TermType::FUNCALL, [
      Func.arity5 { |a, b, c, d, e| yield(a, b, c, d, e) },
      args[0], args[1], args[2], args[3], args[4],
    ])
  end

  def self.branch(*args)
    DatumTerm.new(TermType::BRANCH, args.to_a)
  end

  def self.error(reason)
    ErrorTerm.new(TermType::ERROR, [reason])
  end

  def self.error
    ErrorTerm.new(TermType::ERROR)
  end

  def self.js(code)
    DatumTerm.new(TermType::JAVASCRIPT, [code])
  end

  def self.js(code, options)
    DatumTerm.new(TermType::JAVASCRIPT, [code], options)
  end

  def self.object(*args)
    DatumTerm.new(TermType::OBJECT, args.to_a)
  end

  def self.uuid
    DatumTerm.new(TermType::UUID)
  end

  def self.uuid(source)
    DatumTerm.new(TermType::UUID, [source])
  end

  def self.epoch_time(time)
    DatumTerm.new(TermType::EPOCH_TIME, [time])
  end

  def self.asc(thing)
    DatumTerm.new(TermType::ASC, [thing])
  end

  def self.desc(thing)
    DatumTerm.new(TermType::DESC, [thing])
  end

  def self.literal
    DatumTerm.new(TermType::LITERAL)
  end

  def self.literal(any)
    DatumTerm.new(TermType::LITERAL, [any])
  end

  def self.time(*args)
    DatumTerm.new(TermType::TIME, args.to_a)
  end

  def self.iso8601(a)
    DatumTerm.new(TermType::ISO8601, [a])
  end

  def self.iso8601(a, **options)
    DatumTerm.new(TermType::ISO8601, [a], options)
  end

  def self.monday
    DatumTerm.new(TermType::MONDAY)
  end

  def self.tuesday
    DatumTerm.new(TermType::TUESDAY)
  end

  def self.wednesday
    DatumTerm.new(TermType::WEDNESDAY)
  end

  def self.thursday
    DatumTerm.new(TermType::THURSDAY)
  end

  def self.friday
    DatumTerm.new(TermType::FRIDAY)
  end

  def self.saturday
    DatumTerm.new(TermType::SATURDAY)
  end

  def self.sunday
    DatumTerm.new(TermType::SUNDAY)
  end

  def self.january
    DatumTerm.new(TermType::JANUARY)
  end

  def self.february
    DatumTerm.new(TermType::FEBRUARY)
  end

  def self.march
    DatumTerm.new(TermType::MARCH)
  end

  def self.april
    DatumTerm.new(TermType::APRIL)
  end

  def self.may
    DatumTerm.new(TermType::MAY)
  end

  def self.june
    DatumTerm.new(TermType::JUNE)
  end

  def self.july
    DatumTerm.new(TermType::JULY)
  end

  def self.august
    DatumTerm.new(TermType::AUGUST)
  end

  def self.september
    DatumTerm.new(TermType::SEPTEMBER)
  end

  def self.october
    DatumTerm.new(TermType::OCTOBER)
  end

  def self.november
    DatumTerm.new(TermType::NOVEMBER)
  end

  def self.december
    DatumTerm.new(TermType::DECEMBER)
  end

  macro define_prefix_notation(*names)
    {% for name in names %}
      def self.{{name.id}}(target, *args, **kargs)
        r(target).{{name.id}}(*args, **kargs)
      end

      def self.{{name.id}}(target, *args, **kargs)
        r(target).{{name.id}}(*args, **kargs) {|*x| yield(*x) }
      end
    {% end %}
  end

  define_prefix_notation type_of, count
  define_prefix_notation add, sub, mul, div, mod
  define_prefix_notation floor, ceil, round
  define_prefix_notation gt, ge, lt, le, eq, ne
  define_prefix_notation and, or, not
  define_prefix_notation max, min, avg, sum
  define_prefix_notation group, distinct, contains
end

struct Number
  def +(other : RethinkDB::DatumTerm)
    r(self) + other
  end

  def -(other : RethinkDB::DatumTerm)
    r(self) - other
  end

  def *(other : RethinkDB::DatumTerm)
    r(self) * other
  end

  def /(other : RethinkDB::DatumTerm)
    r(self) / other
  end

  def %(other : RethinkDB::DatumTerm)
    r(self) % other
  end
end

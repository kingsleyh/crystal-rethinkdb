require "./term"

module RethinkDB
  class RowsTerm < StreamTerm
    def update
      DatumTerm.new(TermType::UPDATE, [self, Func.arity1 { |row| yield(row) }])
    end

    def update(doc, options : Hash | NamedTuple)
      DatumTerm.new(TermType::UPDATE, [self, doc], options)
    end

    def update(doc, **options)
      DatumTerm.new(TermType::UPDATE, [self, doc], options)
    end

    def update(options : Hash | NamedTuple)
      DatumTerm.new(TermType::UPDATE, [self, Func.arity1 { |row| yield(row) }], options)
    end

    def replace(doc)
      DatumTerm.new(TermType::REPLACE, [self, doc])
    end

    def replace
      DatumTerm.new(TermType::REPLACE, [self, Func.arity1 { |row| yield(row) }])
    end

    def filter(callable)
      RowsTerm.new(TermType::FILTER, [self, callable])
    end

    def delete
      RowsTerm.new(TermType::DELETE, [self])
    end

    def filter
      RowsTerm.new(TermType::FILTER, [self, Func.arity1 { |row| yield(row) }])
    end

    def filter(**kargs)
      RowsTerm.new(TermType::FILTER, [self, Func.arity1 { |row| yield(row) }], kargs)
    end

    def get_all(*args, **kargs)
      RowsTerm.new(TermType::GET_ALL, [self] + args.to_a, kargs)
    end

    def get_all(args, **kargs)
      RowsTerm.new(TermType::GET_ALL, [self] + args, kargs)
    end

    def changes(**kargs)
      ChangesTerm.new(TermType::CHANGES, [self], kargs)
    end
  end
end

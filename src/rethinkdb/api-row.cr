require "./term"

module RethinkDB
  class RowTerm < DatumTerm
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

    def delete
      DatumTerm.new(TermType::DELETE, [self])
    end

    def changes(**kargs)
      ChangesTerm.new(TermType::CHANGES, [self], kargs)
    end
  end
end

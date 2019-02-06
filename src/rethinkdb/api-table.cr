require "./term"

module RethinkDB
  class TableTerm < RowsTerm
    def info
      RowTerm.new(TermType::INFO, [self])
    end

    def insert(doc, **options)
      DatumTerm.new(TermType::INSERT, [self, doc], options)
    end

    def get(key)
      RowTerm.new(TermType::GET, [self, key])
    end

    def delete
      DatumTerm.new(TermType::DELETE, [self])
    end

    def index_create(key)
      DatumTerm.new(TermType::INDEX_CREATE, [self, key])
    end

    def index_create(key, **options)
      DatumTerm.new(TermType::INDEX_CREATE, [self, key], options)
    end

    def index_create(key, **options)
      DatumTerm.new(TermType::INDEX_CREATE, [self, key, Func.arity1 { |row| yield(row) }], options)
    end

    def index_wait(name)
      DatumTerm.new(TermType::INDEX_WAIT, [self, name])
    end

    def index_list
      DatumTerm.new(TermType::INDEX_LIST, [self])
    end

    def sample(number : Int32)
      DatumTerm.new(TermType::SAMPLE, [self, number])
    end
  end
end

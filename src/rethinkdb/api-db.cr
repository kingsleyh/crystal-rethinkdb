require "./term"

module RethinkDB
  def self.table(name)
    TableTerm.new(TermType::TABLE, [name])
  end

  def self.table_create(name)
    DatumTerm.new(TermType::TABLE_CREATE, [name])
  end

  def self.table_create(name, **opts)
    DatumTerm.new(TermType::TABLE_CREATE, [name], opts)
  end

  def self.table_drop(name)
    DatumTerm.new(TermType::TABLE_DROP, [name])
  end

  def self.table_list
    DatumTerm.new(TermType::TABLE_LIST)
  end

  def self.json(json_string : String)
    DatumTerm.new(TermType::JSON, [json_string])
  end

  class DBTerm < Term
    def table(name)
      TableTerm.new(TermType::TABLE, [self, name])
    end

    def table_create(name)
      DatumTerm.new(TermType::TABLE_CREATE, [self, name])
    end

    def table_create(name, **opts)
      DatumTerm.new(TermType::TABLE_CREATE, [name], opts)
    end

    def table_drop(name)
      DatumTerm.new(TermType::TABLE_DROP, [self, name])
    end

    def table_list
      DatumTerm.new(TermType::TABLE_LIST, [self])
    end
  end
end

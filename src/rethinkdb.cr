# Require each file individually so as to prevent including extraneous files
require "./rethinkdb/api-datum"
require "./rethinkdb/api-db"
require "./rethinkdb/api-global"
require "./rethinkdb/api-grouped"
require "./rethinkdb/api-row"
require "./rethinkdb/api-rows"
require "./rethinkdb/api-stream"
require "./rethinkdb/api-table"
require "./rethinkdb/api-term"
require "./rethinkdb/auth"
require "./rethinkdb/connection"
require "./rethinkdb/constants"
require "./rethinkdb/crypto"
require "./rethinkdb/cursor"
require "./rethinkdb/error"
require "./rethinkdb/message"
require "./rethinkdb/serialization"
require "./rethinkdb/term"

module RethinkDB
  module Shortcuts
    def r
      RethinkDB
    end

    def r(any)
      r.expr(any)
    end
  end

  def self.connect(**options)
    Connection.new(**options)
  end
end

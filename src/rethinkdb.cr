require "./rethinkdb/*"

module RethinkDB
  module Reql
    def self.connect(host : String = "localhost", port : Int32 = 28015, db : String = "test", user : String = "admin", password : String = "")
      conn = Connection.new(host, port)
      conn.authorise(user, password)
      # conn.use(opts["db"].as(String))
      conn.start
      conn
    end
  end

  module Shortcuts
    def r
      Reql
    end
  end
end

include RethinkDB::Shortcuts
p r.connect(host: "localhost", user: "bob", password: "secret")

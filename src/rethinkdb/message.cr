require "json"

module RethinkDB
  # :nodoc:
  private abstract struct Message
    include JSON::Serializable
    include JSON::Serializable::Strict
  end
end

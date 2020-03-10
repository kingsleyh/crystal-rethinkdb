require "./constants"
require "./serialization"

module RethinkDB
  class Cursor
    include Iterator(QueryResult)

    private property index : Int32 = 0
    private property stopped : Bool = false
    private property response
    private getter stream

    def initialize(@stream : Connection::ResponseStream, @response : Connection::Response)
    end

    def stop
      self.stopped = true
      stream.conn.delete_channel(stream.id).try &.close
      super
    end

    def fetch_next
      self.response = stream.query_continue
      self.index = 0

      unless response.t.in? [ResponseType::SUCCESS_SEQUENCE, ResponseType::SUCCESS_PARTIAL]
        raise ReqlDriverError.new("Expected SUCCESS_SEQUENCE or SUCCESS_PARTIAL but got #{response.t}")
      end

      true
    rescue e
      # Do not raise after iteration stonpped
      raise e unless stopped
      false
    end

    def next
      return stop if stopped
      while index == response.r.size
        return stop if response.t == ResponseType::SUCCESS_SEQUENCE
        return stop unless fetch_next
      end

      value = response.r[index]
      @index += 1
      value
    end
  end
end

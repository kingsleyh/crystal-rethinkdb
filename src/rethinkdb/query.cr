module RethinkDB

  enum QueryType
    START        = 1
    CONTINUE     = 2
    STOP         = 3
    NOREPLY_WAIT = 4
    SERVER_INFO  = 5
  end

  enum ResponseType
    SUCCESS_ATOM     =  1
    SUCCESS_SEQUENCE =  2
    SUCCESS_PARTIAL  =  3
    WAIT_COMPLETE    =  4
    SERVER_INFO      =  5
    CLIENT_ERROR     = 16
    COMPILE_ERROR    = 17
    RUNTIME_ERROR    = 18
  end

  enum ErrorType
    INTERNAL         = 1000000
    RESOURCE_LIMIT   = 2000000
    QUERY_LOGIC      = 3000000
    NON_EXISTENCE    = 3100000
    OP_FAILED        = 4100000
    OP_INDETERMINATE = 4200000
    USER             = 5000000
    PERMISSION_ERROR = 6000000
  end

  class Query
    getter id : UInt64
    @channel : Channel::Unbuffered(String)

    def initialize(@conn : Connection, @runopts : RunOpts)
      @id = @conn.next_query_id
      @channel = @conn.@channels[id] = Channel(String).new
    end

    # def start(term)
    #   send [QueryType::START, ReQL::Term.encode(term), @runopts].to_json
    #   read
    # end

    def continue
      send [QueryType::CONTINUE].to_json
      read
    end

    private def send(query)
      if @id == 0
        raise "Bug: Using already finished stream."
      end

      @conn.@socket.write_bytes(@id, IO::ByteFormat::LittleEndian)
      @conn.@socket.write_bytes(query.bytesize, IO::ByteFormat::LittleEndian)
      @conn.@socket.write(query.to_slice)
    end

    private def read
      response = Response.from_json(@channel.receive)
      finish unless response.t == ResponseType::SUCCESS_PARTIAL

      if response.t == ResponseType::CLIENT_ERROR
        raise ReqlError::ClientError.new(response.r[0].to_s)
      elsif response.t == ResponseType::COMPILE_ERROR
        raise ReqlError::ReqlCompileError.new(response.r[0].to_s)
      elsif response.t == ResponseType::RUNTIME_ERROR
        msg = response.r[0].to_s
        case response.e
        when ErrorType::INTERNAL        ; raise ReqlError::ReqlRuntimeError::ReqlInternalError.new msg
        when ErrorType::RESOURCE_LIMIT  ; raise ReqlError::ReqlRuntimeError::ReqlResourceLimitError.new msg
        when ErrorType::QUERY_LOGIC     ; raise ReqlError::ReqlRuntimeError::ReqlQueryLogicError.new msg
        when ErrorType::NON_EXISTENCE   ; raise ReqlError::ReqlRuntimeError::ReqlQueryLogicError::ReqlNonExistenceError.new msg
        when ErrorType::OP_FAILED       ; raise ReqlError::ReqlRuntimeError::ReqlAvailabilityError::ReqlOpFailedError.new msg
        when ErrorType::OP_INDETERMINATE; raise ReqlError::ReqlRuntimeError::ReqlAvailabilityError::ReqlOpIndeterminateError.new msg
        when ErrorType::USER            ; raise ReqlError::ReqlRuntimeError::ReqlUserError.new msg
        when ErrorType::PERMISSION_ERROR; raise ReqlError::ReqlRuntimeError::ReqlPermissionsError.new msg
        else
          raise ReqlError::RuntimeError.new(response.e.to_s + ": " + msg)
        end
      end

      # response.r = response.r.map &.transformed(
      #   time_format: @runopts["time_format"]? || "native",
      #   group_format: @runopts["group_format"]? || "native",
      #   binary_format: @runopts["binary_format"]? || "native"
      # )

      response
    end

    private def finish
      @conn.@channels.delete @id
      @id = 0u64
    end
  end
end

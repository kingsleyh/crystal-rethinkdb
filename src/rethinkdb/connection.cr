require "socket"
require "socket/tcp_socket"
require "json"
require "./serialization"
require "./constants"
require "./crypto"

module RethinkDB
  class ConnectionException < Exception
  end

  class ConnectionResponse
    JSON.mapping(
      max_protocol_version: Int32,
      min_protocol_version: Int32,
      server_version: String,
      success: Bool
    )

    def self._from_json(json)
      ConnectionResponse.from_json(json.not_nil!)
    rescue error
      raise ConnectionException.new(json)
    end
  end

  class AuthMessage1
    def initialize(@protocol_version : Int32, @authentication_method : String, @authentication : String)
    end

    JSON.mapping(
      protocol_version: Int32,
      authentication_method: String,
      authentication: String
    )
  end

  class AuthMessageErrorResponse
    JSON.mapping(
      error: String,
      error_code: Int64,
      success: Bool
    )
  end

  class AuthMessage1SuccessResponse
    JSON.mapping(
      authentication: String,
      success: Bool
    )

    def r
      value_for("r")
    end

    def s
      Base64.decode(value_for("s"))
    end

    def i
      value_for("i").to_i
    end

    private def value_for(target : String)
      authentication.split(",").find(if_none: "") { |x| x.starts_with?("#{target}=") }.split("#{target}=").last
    end
  end

  class AuthMessage3
    def initialize(nonce : String, encoded_password : String)
      @authentication = "c=biws,r=#{nonce},p=#{encoded_password}"
    end

    JSON.mapping(
      authentication: String
    )
  end

  class AuthMessage3SuccessResponse
    JSON.mapping(
      authentication: String,
      success: Bool
    )

    def v
      authentication.split("v=").last
    end
  end

  class Connection
    def initialize(options)
      host = options[:host]? || "localhost"
      port = options[:port]? || 28015
      @db = options[:db]? || "test"
      user = options[:user]? || "admin"
      password = options[:password]? || ""

      @next_id = 1u64
      @open = true

      @sock = TCPSocket.new(host, port)

      connect
      authorise(user, password)

      @channels = {} of UInt64 => Channel::Unbuffered(String)
      @next_query_id = 1_u64

      spawn do
        while @open
          id = @sock.read_bytes(UInt64, IO::ByteFormat::LittleEndian)
          size = @sock.read_bytes(UInt32, IO::ByteFormat::LittleEndian)
          slice = Slice(UInt8).new(size)
          @sock.read_fully(slice)
          @channels[id]?.try &.send String.new(slice)
        end
        @sock.close
      end
    end

    private def connect : ConnectionResponse
      protocol_version_bytes = Bytes.new(4)
      IO::ByteFormat::LittleEndian.encode(0x34c2bdc3_u32, protocol_version_bytes)
      write(protocol_version_bytes)
      response = ConnectionResponse._from_json(read)
      raise ConnectionException.new("Connection could not be established: #{response}") if response.success != true
      response
    end

    private def authorise(user : String, password : String)
      client_nonce = Random::Secure.base64(14)
      message1 = "n,,n=#{user},r=#{client_nonce}"
      write((AuthMessage1.new(0, "SCRAM-SHA-256", message1).to_json + "\0").to_slice)
      json = JSON.parse(data1 = read)

      if (json["success"].as_bool)
        response = AuthMessage1SuccessResponse.from_json(data1)
        combined_nonce = response.r
        salt = response.s
        iteration_count = response.i

        client_key = hmac_sha256(pbkdf2_hmac_sha256(password, salt, iteration_count), "Client Key")
        stored_key = sha256(client_key)
        message3_start = "c=biws,r=#{combined_nonce}"
        auth_message = message1[3..-1] + "," + response.authentication + "," + message3_start
        client_signature = hmac_sha256(stored_key, auth_message)
        client_proof = Bytes.new(client_signature.size)
        client_proof.size.times do |i|
          client_proof[i] = client_key[i] ^ client_signature[i]
        end

        write((AuthMessage3.new(combined_nonce, Base64.strict_encode(client_proof)).to_json + "\0").to_slice)
        json = JSON.parse(data2 = read)
        if (json["success"].as_bool)
          AuthMessage3SuccessResponse.from_json(data2)
        else
          error = AuthMessageErrorResponse.from_json(data2)
          raise ReqlError::ReqlDriverError::ReqlAuthError.new("error_code: #{error.error_code}, error: #{error.error}")
        end
      else
        error = AuthMessageErrorResponse.from_json(data1)
        raise ReqlError::ReqlDriverError::ReqlAuthError.new("error_code: #{error.error_code}, error: #{error.error}")
      end
    end

    private def write(data)
      @sock.write(data)
    end

    private def read
      @sock.gets('\0', true).not_nil!
    end

    def close
      @open = false
    end

    protected def next_id
      id = @next_id
      @next_id += 1
      id
    end

    class Response
      JSON.mapping({
        t: ResponseType,
        r: Array(QueryResult),
        e: {type: ErrorType, nilable: true},
        b: {type: Array(JSON::Any), nilable: true},
        p: {type: JSON::Any, nilable: true},
        n: {type: Array(ResponseNote), nilable: true},
      })

      def cfeed?
        notes = (self.n || [] of ResponseNote)
        !(notes & [ResponseNote::SEQUENCE_FEED, ResponseNote::ATOM_FEED, ResponseNote::ORDER_BY_LIMIT_FEED, ResponseNote::UNIONED_FEED]).empty?
      end
    end

    class ResponseStream
      getter id : UInt64
      @channel : Channel::Unbuffered(String)
      @runopts : Hash(String, JSON::Any)

      def initialize(@conn : Connection, runopts)
        @id = @conn.next_id
        @channel = @conn.@channels[id] = Channel(String).new
        @runopts = {} of String => JSON::Any
        runopts.each do |key, val|
          @runopts[key] = JSON.parse(val.to_json)
        end
        @runopts["db"] = RethinkDB.db(@conn.@db).to_reql
      end

      def query_term(term)
        send_query [QueryType::START, term.to_reql, @runopts].to_json
        read_response
      end

      def query_continue
        send_query [QueryType::CONTINUE].to_json
        read_response
      end

      private def send_query(query)
        if @id == 0
          raise ReqlDriverError.new("Bug: Using already finished stream.")
        end

        @conn.@sock.write_bytes(@id, IO::ByteFormat::LittleEndian)
        @conn.@sock.write_bytes(query.bytesize, IO::ByteFormat::LittleEndian)
        @conn.@sock.write(query.to_slice)
      end

      private def read_response
        response = Response.from_json(@channel.receive)
        finish unless response.t == ResponseType::SUCCESS_PARTIAL

        if response.t == ResponseType::CLIENT_ERROR
          raise ReqlClientError.new(response.r[0].to_s)
        elsif response.t == ResponseType::COMPILE_ERROR
          raise ReqlCompileError.new(response.r[0].to_s)
        elsif response.t == ResponseType::RUNTIME_ERROR
          msg = response.r[0].to_s
          case response.e
          when ErrorType::QUERY_LOGIC
            raise ReqlQueryLogicError.new(msg)
          when ErrorType::USER
            raise ReqlUserError.new(msg)
          when ErrorType::NON_EXISTENCE
            raise ReqlNonExistenceError.new(msg)
          else
            raise ReqlRunTimeError.new(response.e.to_s + ": " + msg)
          end
        end

        response.r = response.r.map &.transformed(
          time_format: @runopts["time_format"]?.try(&.as_s) || "native",
          group_format: @runopts["group_format"]?.try(&.as_s) || "native",
          binary_format: @runopts["binary_format"]?.try(&.as_s) || "native",
        )

        response
      end

      private def finish
        @conn.@channels.delete @id
        @id = 0u64
      end
    end

    def query_error(term, runopts)
      stream = ResponseStream.new(self, runopts)
      stream.query_term(term)

      raise ReqlDriverError.new("An r.error should never return successfully")
    end

    def query_datum(term, runopts)
      stream = ResponseStream.new(self, runopts)
      response = stream.query_term(term)

      unless response.t == ResponseType::SUCCESS_ATOM
        raise ReqlDriverError.new("Expected SUCCESS_ATOM but got #{response.t}")
      end

      response.r[0]
    end

    def query_cursor(term, runopts)
      stream = ResponseStream.new(self, runopts)
      response = stream.query_term(term)

      unless response.t == ResponseType::SUCCESS_SEQUENCE || response.t == ResponseType::SUCCESS_PARTIAL || response.t == ResponseType::SUCCESS_ATOM
        raise ReqlDriverError.new("Expected SUCCESS_SEQUENCE or SUCCESS_PARTIAL or SUCCESS_ATOM but got #{response.t}")
      end

      Cursor.new(stream, response)
    end

    def query_changefeed(term, runopts)
      stream = ResponseStream.new(self, runopts)
      response = stream.query_term(term)

      unless response.cfeed?
        raise ReqlDriverError.new("Expected SEQUENCE_FEED, ATOM_FEED, ORDER_BY_LIMIT_FEED or UNIONED_FEED but got #{response.n} ")
      end

      unless response.t == ResponseType::SUCCESS_PARTIAL
        raise ReqlDriverError.new("Expected SUCCESS_SEQUENCE or SUCCESS_PARTIAL or SUCCESS_ATOM but got #{response.t}")
      end

      Cursor.new(stream, response)
    end
  end

  class Cursor
    include Iterator(QueryResult)

    def initialize(@stream : Connection::ResponseStream, @response : Connection::Response)
      @index = 0
    end

    def fetch_next
      @response = @stream.query_continue
      @index = 0

      unless @response.t == ResponseType::SUCCESS_SEQUENCE || @response.t == ResponseType::SUCCESS_PARTIAL
        raise ReqlDriverError.new("Expected SUCCESS_SEQUENCE or SUCCESS_PARTIAL but got #{@response.t}")
      end
    end

    def next
      while @index == @response.r.size
        return stop if @response.t == ResponseType::SUCCESS_SEQUENCE
        fetch_next
      end

      value = @response.r[@index]
      @index += 1
      value
    end
  end
end

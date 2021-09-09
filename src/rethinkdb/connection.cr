require "json"
require "log"
require "retriable"
require "socket"
require "socket/tcp_socket"

require "./auth"
require "./constants"
require "./crypto"
require "./cursor"
require "./error"
require "./message"
require "./serialization"

module RethinkDB
  class Connection
    Log = ::Log.for(self)

    # Authentication
    getter user
    private getter password
    # Connection
    getter host
    getter port
    getter db
    # Reconnection
    getter max_retry_interval
    getter max_retry_attempts

    protected property channels = {} of UInt64 => Channel(String)

    protected getter sock : TCPSocket
    private getter? open : Bool = true

    def initialize(
      @host : String = "localhost",
      @port : Int32 = 28015,
      @db : String = "test",
      @user : String = "admin",
      @password : String = "",
      @max_retry_interval : Time::Span = 2.seconds,
      @max_retry_attempts : Int32? = nil
    )
      @next_id = 1_u64
      @sock = TCPSocket.new(host, port)
      sock.sync = false
      connect
      authorise(user, password)

      spawn { read_loop }
    end

    def close
      @open = false
    end

    private def read_loop
      Retriable.retry(max_interval: max_retry_interval) do
        begin
          while open?
            id = sock.read_bytes(UInt64, IO::ByteFormat::LittleEndian)
            size = sock.read_bytes(UInt32, IO::ByteFormat::LittleEndian)
            slice = Slice(UInt8).new(size)
            sock.read_fully(slice)

            channel = channel_lock.synchronize { channels[id]? }
            channel.try &.send String.new(slice)
          end
          sock.close
        rescue e
          Log.error(exception: e) { "reconnecting" }
          sock.close
          reconnect
          raise e
        end
      end
    end

    private def connect : ConnectionResponse
      protocol_version_bytes = Bytes.new(4)
      IO::ByteFormat::LittleEndian.encode(0x34c2bdc3_u32, protocol_version_bytes)
      write(protocol_version_bytes)
      response = ConnectionResponse.from_json(read)
      raise ConnectionException.new("Connection could not be established: #{response}") if response.success != true
      response
    end

    private def authorise(user : String, password : String)
      client_nonce = Random::Secure.base64(14)
      message1 = "n,,n=#{user},r=#{client_nonce}"
      write((Auth::Message1.new(0, "SCRAM-SHA-256", message1).to_json + "\0").to_slice)
      json = JSON.parse(data1 = read)

      if (json["success"].as_bool)
        response = Auth::Message1SuccessResponse.from_json(data1)
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

        write((Auth::Message3.new(combined_nonce, Base64.strict_encode(client_proof)).to_json + "\0").to_slice)
        json = JSON.parse(data2 = read)
        if (json["success"].as_bool)
          Auth::Message3SuccessResponse.from_json(data2)
        else
          error = Auth::MessageErrorResponse.from_json(data2)
          raise ReqlError::ReqlDriverError::ReqlAuthError.new("error_code: #{error.error_code}, error: #{error.error}")
        end
      else
        error = Auth::MessageErrorResponse.from_json(data1)
        raise ReqlError::ReqlDriverError::ReqlAuthError.new("error_code: #{error.error_code}, error: #{error.error}")
      end
    end

    protected getter write_lock = Mutex.new(Mutex::Protection::Reentrant)

    protected def write(data)
      try_write do
        sock.write(data)
        sock.flush
      end
    end

    protected def reconnect
      write_lock.synchronize do
        return unless sock.closed?

        reset_channels
        reset_id

        # Create a new socket
        @sock = TCPSocket.new(host, port)
        sock.sync = false
        connect
        authorise(user, password)
      end
    end

    protected def try_write
      write_lock.synchronize {
        yield
      }
    rescue e
      sock.close
      reconnect
      raise e
    end

    protected def read
      sock.gets('\0', true).not_nil!
    rescue e : NilAssertionError
      sock.close
      raise ConnectionException.new("Socket closed")
    end

    @next_id : UInt64 = 1_u64

    private getter id_lock = Mutex.new

    protected def reset_id
      id_lock.synchronize {
        @next_id = 1_u64
      }
    end

    protected def next_id
      id_lock.synchronize {
        id = @next_id
        @next_id += 1
        id
      }
    end

    private getter channel_lock = Mutex.new

    protected def add_channel(id : UInt64)
      channel = Channel(String).new
      channel_lock.synchronize {
        channels[id] = channel
      }
      channel
    end

    protected def delete_channel(id : UInt64)
      channel_lock.synchronize {
        channels.delete(id)
      }
    end

    protected def reset_channels
      channel_lock.synchronize do
        channels.each_value &.close
        channels.clear
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

      unless response.changefeed?
        raise ReqlDriverError.new("Expected SEQUENCE_FEED, ATOM_FEED, ORDER_BY_LIMIT_FEED or UNIONED_FEED but got #{response.n} ")
      end

      unless response.t == ResponseType::SUCCESS_PARTIAL
        raise ReqlDriverError.new("Expected SUCCESS_SEQUENCE or SUCCESS_PARTIAL or SUCCESS_ATOM but got #{response.t}")
      end

      Cursor.new(stream, response)
    end

    struct ConnectionResponse < Message
      getter max_protocol_version : Int32
      getter min_protocol_version : Int32
      getter server_version : String
      getter success : Bool

      def self.from_json(json)
        raise ConnectionException.new(json) if json.nil?
        super(json)
      end
    end

    struct Response < Message
      {% if compare_versions(Crystal::VERSION, "0.36.1") == 1 %}
        @[JSON::Field(converter: Enum::ValueConverter(RethinkDB::ResponseType))]
      {% end %}
      getter t : RethinkDB::ResponseType
      getter r : Array(QueryResult)
      {% if compare_versions(Crystal::VERSION, "0.36.1") == 1 %}
        @[JSON::Field(converter: Enum::ValueConverter(RethinkDB::ErrorType))]
      {% end %}
      getter e : ErrorType?
      getter b : Array(JSON::Any)?
      getter p : JSON::Any?
      {% if compare_versions(Crystal::VERSION, "0.36.1") == 1 %}
        @[JSON::Field(converter: ArrayConverter(Enum::ValueConverter(RethinkDB::ResponseNote)))]
      {% end %}
      getter n : Array(RethinkDB::ResponseNote) = [] of RethinkDB::ResponseNote

      private FEED_NOTES = [
        ResponseNote::SEQUENCE_FEED,
        ResponseNote::ATOM_FEED,
        ResponseNote::ORDER_BY_LIMIT_FEED,
        ResponseNote::UNIONED_FEED,
      ]

      def changefeed?
        !(n | FEED_NOTES).empty?
      end

      protected def validate!(runopts)
        check_errored!
        set_formatting(runopts)
        self
      end

      private def set_formatting(runopts)
        r.map! &.transformed(
          time_format: runopts["time_format"]?.try(&.as_s) || "native",
          group_format: runopts["group_format"]?.try(&.as_s) || "native",
          binary_format: runopts["binary_format"]?.try(&.as_s) || "native",
        )
      end

      private def check_errored!
        message = r[0]?.to_s
        case t
        when ResponseType::CLIENT_ERROR  then raise ReqlClientError.new(message)
        when ResponseType::COMPILE_ERROR then raise ReqlCompileError.new(message)
        when ResponseType::RUNTIME_ERROR
          case e
          when ErrorType::QUERY_LOGIC   then raise ReqlQueryLogicError.new(message)
          when ErrorType::USER          then raise ReqlUserError.new(message)
          when ErrorType::NON_EXISTENCE then raise ReqlNonExistenceError.new(message)
          when ErrorType::OP_FAILED     then raise ReqlOpFailedError.new(message)
          else                               raise ReqlRunTimeError.new("#{e}:#{message}")
          end
        end
        self
      end
    end

    struct ResponseStream
      getter id : UInt64

      private getter channel : Channel(String)

      protected getter conn

      protected getter runopts : Hash(String, JSON::Any)

      def initialize(@conn : Connection, runopts)
        @id = conn.next_id

        @channel = conn.add_channel(id)

        @runopts = {} of String => JSON::Any
        runopts.each do |key, val|
          @runopts[key] = JSON.parse(val.to_json)
        end
        @runopts["db"] = RethinkDB.db(conn.@db).to_reql
      end

      def query_term(term)
        send_query QueryType::START, term.to_reql, runopts
        read_response
      end

      def query_continue
        send_query QueryType::CONTINUE
        read_response
      end

      private def send_query(type : QueryType, *rest)
        raise ReqlDriverError.new("Bug: Using already finished stream.") if id.zero?

        query_slice = ({type.value} + rest).to_json.to_slice
        conn.try_write do
          conn.sock.write_bytes(id, IO::ByteFormat::LittleEndian)
          conn.sock.write_bytes(query_slice.size, IO::ByteFormat::LittleEndian)
          conn.sock.write(query_slice)
          conn.sock.flush
        end
      end

      private def read_response
        response = Response.from_json(channel.receive)
        finish unless response.t == ResponseType::SUCCESS_PARTIAL

        response.validate!(runopts)
      rescue e
        finish
        raise e
      end

      private def finish
        conn.delete_channel(id)
        @id = 0_u64
      end
    end
  end
end

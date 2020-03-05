require "json"
require "retriable"
require "socket"
require "socket/tcp_socket"

require "./constants"
require "./crypto"
require "./serialization"

module RethinkDB
  class ConnectionException < Exception
  end

  private abstract struct Message
    include JSON::Serializable
    include JSON::Serializable::Strict
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

  struct AuthMessage1 < Message
    getter protocol_version : Int32
    getter authentication_method : String
    getter authentication : String

    def initialize(
      @protocol_version : Int32,
      @authentication_method : String,
      @authentication : String
    )
    end
  end

  struct AuthMessageErrorResponse < Message
    getter error : String
    getter error_code : Int64
    getter success : Bool
  end

  struct AuthMessage1SuccessResponse < Message
    getter authentication : String
    getter success : Bool

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
      authentication.split(",").find(if_none: "") { |f|
        f.starts_with?("#{target}=")
      }.split("#{target}=").last
    end
  end

  struct AuthMessage3 < Message
    getter authentication : String

    def initialize(nonce : String, encoded_password : String)
      @authentication = "c=biws,r=#{nonce},p=#{encoded_password}"
    end
  end

  struct AuthMessage3SuccessResponse < Message
    getter authentication : String
    getter success : Bool

    def v
      authentication.split("v=").last
    end
  end

  class Connection
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

    private def read_loop
      Retriable.retry(max_interval: max_retry_interval, max_attempts: max_retry_attempts) do
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
          sock.close
          write_lock.synchronize do
            reset_channels
            reset_id
            # Create a new socket
            @sock = TCPSocket.new(host, port)
            sock.sync = false
            connect
            authorise(user, password)
          end
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

    protected getter write_lock = Mutex.new(Mutex::Protection::Reentrant)

    protected def write(data)
      write_lock.synchronize {
        sock.write(data)
        sock.flush
      }
    end

    protected def read
      sock.gets('\0', true).not_nil!
    end

    def close
      @open = false
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

    struct Response < Message
      getter t : RethinkDB::ResponseType
      getter r : Array(QueryResult)
      getter e : ErrorType?
      getter b : Array(JSON::Any)?
      getter p : JSON::Any?
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
        send_query [QueryType::START, term.to_reql, runopts].to_json
        read_response
      end

      def query_continue
        send_query [QueryType::CONTINUE].to_json
        read_response
      end

      private def send_query(query)
        if id == 0
          raise ReqlDriverError.new("Bug: Using already finished stream.")
        end

        query_slice = query.to_slice
        conn.write_lock.synchronize {
          conn.sock.write_bytes(id, IO::ByteFormat::LittleEndian)
          conn.sock.write_bytes(query_slice.size, IO::ByteFormat::LittleEndian)
          conn.sock.write(query_slice)
          conn.sock.flush
        }
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

require "socket"
require "json"
require "./crypto"
require "./exceptions"

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
   begin
      ConnectionResponse.from_json(json.not_nil!)
   rescue error
     raise ConnectionException.new(json)
   end
  end
end

class AuthMessage1
  def initialize(@protocol_version : Int32, @authentication_method : String, @authentication : String)
  end
  JSON.mapping(
    protocol_version:      Int32,
    authentication_method: String,
    authentication:        String
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
    authentication.split(",").select{|x| x.starts_with?("#{target}=")}.first.split("#{target}=").last
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

  V1_0 = 0x34c2bdc3_u32

  getter connection_details : ConnectionResponse

  def initialize(host : String, port : Int32)
    @socket = TCPSocket.new(host, port)
    @connection_details = connect
  end

  def authorise(user : String, password : String)
    client_nonce = Random::Secure.base64(14)
    message1 = "n,,n=#{user},r=#{client_nonce}"
    write((AuthMessage1.new(0, "SCRAM-SHA-256", message1).to_json + "\0").to_slice)
    json = JSON.parse(data1 = read)

    if(json["success"].as_bool)
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
      if(json["success"].as_bool)
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

  private def connect : ConnectionResponse
    protocol_version_bytes = Bytes.new(4)
    IO::ByteFormat::LittleEndian.encode(0x34c2bdc3_u32, protocol_version_bytes)
    write(protocol_version_bytes)
    response = ConnectionResponse._from_json(read)
    raise ConnectionException.new("Connection could not be established: #{response}") if response.success != true
    response
  end

  def write(data)
    @socket.write(data)
  end

  def read
    @socket.gets('\0', true).not_nil!
  end

  def close
    @socket.close
  end
end


c = Connection.new("localhost", 28015)
c.connection_details
p c.authorise("cat", "secret")

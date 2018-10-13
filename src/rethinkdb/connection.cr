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

class AuthMessage1ErrorResponse
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
    # data = read
    json = JSON.parse(data = read)

    if(json["success"].as_bool)
      response = AuthMessage1SuccessResponse.from_json(data)
      iteration_count = response.i
      salt = response.s
      combined_nonce = response.r

      client_key = sha256(hmac_sha256(pbkdf2_hmac_sha256(password.to_slice, salt, iteration_count), "Client Key"))
      message3_start = "c=biws,r=#{combined_nonce}"
      auth_message = message1[3..-1] + "," + response.authentication + "," + message3_start
      client_signature = hmac_sha256(client_key, auth_message)
      client_proof = Bytes.new(client_signature.size)
      client_proof.size.times do |i|
        client_proof[i] = client_key[i] ^ client_signature[i]
      end

      message3 = AuthMessage3.new(combined_nonce, Base64.strict_encode(client_proof))

      p message3.to_json
      # password_hash = pbkdf2_hmac_sha256(password.to_slice, salt, iter)
      #
      # message3_start = "c=biws,r=#{nonce_c}#{nonce_s}"
      #
      # client_key = hmac_sha256(password_hash, "Client Key")
      # stored_key = sha256(client_key)
      # auth_message = message1[3..-1] + "," + message2 + "," + message3_start
      # client_signature = hmac_sha256(stored_key, auth_message)
      # client_proof = Bytes.new(client_signature.size)
      # client_proof.size.times do |i|
      #   client_proof[i] = client_key[i] ^ client_signature[i]
      # end
      #
      # message3 = "c=biws,r=#{nonce_c}#{nonce_s},p=#{Base64.strict_encode(client_proof)}"
      #
    else
      error = AuthMessage1ErrorResponse.from_json(data)
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
p c.authorise("woop", "password")

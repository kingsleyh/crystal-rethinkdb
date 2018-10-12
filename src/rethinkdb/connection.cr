require "socket"
require "json"
require "./crypto"

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

class ScrumAuthMessage1
  JSON.mapping(
    protocol_version:      Int32,
    authentication_method: String,
    authentication:        String
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
    write((ScrumAuthMessage1.new(0, "SCRAM-SHA-256", "n,,n=#{user},r=#{client_nonce}").to_json + "\0").to_slice))
  end

  private def connect : ConnectionResponse
    protocol_version_bytes = Bytes.new(4)
    IO::ByteFormat::LittleEndian.encode(0x34c2bdc3_u32, protocol_version_bytes)
    write(protocol_version_bytes)
    response = ConnectionResponse._from_json(@socket.gets("\0", true))
    raise ConnectionException.new("Connection could not be established: #{response}") if response.success != true
    response
  end

  def write(data)
    @socket.write(data)
  end

  def close
    @socket.close
  end
end


c = Connection.new("localhost", 28015)
c.connection_details
p c.authorise("woop", "password")

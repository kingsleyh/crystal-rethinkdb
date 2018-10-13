require "openssl"
require "openssl/hmac"

# Patch LibCrypto to support more algorithms for pbkdf2 (specifically needed sha256)
lib LibCrypto
  fun pkcs5_pbkdf2_hmac = PKCS5_PBKDF2_HMAC(pass : LibC::Char*, passlen : LibC::Int, salt : UInt8*, saltlen : LibC::Int, iter : LibC::Int, digest : EVP_MD, keylen : LibC::Int, out : UInt8*) : LibC::Int
end

# Patch PKCS5 to support more algorithms for pbkdf2 (specifically needed sha256)
module OpenSSL::PKCS5
  def self.pbkdf2_hmac(algorithm : Symbol, secret, salt, iterations = 2**16, key_size = 64) : Bytes
    evp = case algorithm
          when :md4       then LibCrypto.evp_md4
          when :md5       then LibCrypto.evp_md5
          when :ripemd160 then LibCrypto.evp_ripemd160
          when :sha1      then LibCrypto.evp_sha1
          when :sha224    then LibCrypto.evp_sha224
          when :sha256    then LibCrypto.evp_sha256
          when :sha384    then LibCrypto.evp_sha384
          when :sha512    then LibCrypto.evp_sha512
          else                 raise "Unsupported digest algorithm: #{algorithm}"
          end

    buffer = Bytes.new(key_size)
    if LibCrypto.pkcs5_pbkdf2_hmac(secret, secret.bytesize, salt, salt.bytesize, iterations, evp, key_size, buffer) != 1
      raise OpenSSL::Error.new "pkcs5_pbkdf2_hmac"
    end
    buffer
  end
end

def pbkdf2_hmac_sha256(password, salt, iters)
  OpenSSL::PKCS5.pbkdf2_hmac(:sha256, password, salt, iters, 32)
end

def hmac_sha256(data, key)
  OpenSSL::HMAC.digest(:sha256, data, key)
end

def sha256(data)
  digest = OpenSSL::Digest.new("SHA256")
  digest.update(data)
  digest.digest
end

require "./message"

module RethinkDB
  # Data formats for RethinkDB connection authentication flow
  private module Auth
    struct Message1 < Message
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

    struct MessageErrorResponse < Message
      getter error : String
      getter error_code : Int64
      getter success : Bool
    end

    struct Message1SuccessResponse < Message
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

    struct Message3 < Message
      getter authentication : String

      def initialize(nonce : String, encoded_password : String)
        @authentication = "c=biws,r=#{nonce},p=#{encoded_password}"
      end
    end

    struct Message3SuccessResponse < Message
      getter authentication : String
      getter success : Bool

      def v
        authentication.split("v=").last
      end
    end
  end
end

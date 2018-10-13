require "json"

# ReqlError
#   * ReqlCompileError
#   * ReqlRuntimeError
#       * ReqlQueryLogicError
#           * ReqlNonExistenceError
#       * ReqlResourceLimitError
#       * ReqlUserError
#       * ReqlInternalError
#       * ReqlTimeoutError
#       * ReqlAvailabilityError
#           * ReqlOpFailedError
#           * ReqlOpIndeterminateError
#       * ReqlPermissionsError
#   * ReqlDriverError
#       * ReqlAuthError

class ReqlError < Exception
end

class ReqlError::ReqlCompileError < Exception
end

class ReqlError::ReqlRuntimeError < Exception
end

class ReqlError::ReqlRuntimeError::ReqlQueryLogicError < Exception
end

class ReqlError::ReqlRuntimeError::ReqlResourceLimitError < Exception
end

class ReqlError::ReqlRuntimeError::ReqlUserError < Exception
end

class ReqlError::ReqlRuntimeError::ReqlInternalError < Exception
end

class ReqlError::ReqlRuntimeError::ReqlTimeoutError < Exception
end

class ReqlError::ReqlRuntimeError::ReqlAvailabilityError < Exception
end

class ReqlError::ReqlRuntimeError::ReqlPermissionsError < Exception
end

class ReqlError::ReqlRuntimeError::ReqlAvailabilityError::ReqlOpFailedError < Exception
end

class ReqlError::ReqlRuntimeError::ReqlAvailabilityError::ReqlOpIndeterminateError < Exception
end

class ReqlError::ReqlRuntimeError::ReqlQueryLogicError::ReqlNonExistenceError < Exception
end

class ReqlError::ReqlDriverError < Exception
end

class ReqlError::ReqlDriverError::ReqlAuthError < Exception
end

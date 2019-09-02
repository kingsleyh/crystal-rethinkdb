module RethinkDB
  class ReqlDriverError < Exception
  end

  class ReqlClientError < Exception
  end

  class ReqlCompileError < Exception
  end

  class ReqlRunTimeError < Exception
  end

  class ReqlQueryLogicError < Exception
  end

  class ReqlUserError < Exception
  end

  class ReqlNonExistenceError < Exception
  end

  class ReqlError::ReqlDriverError < Exception
  end

  class ReqlError::ReqlDriverError::ReqlAuthError < Exception
  end

  class ReqlOpFailedError < Exception
  end
end

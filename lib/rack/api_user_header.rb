module Rack
  # Tell the reverse proxy which user a request was authenticated as, so its
  # access log can record it (nginx logs $upstream_http_x_api_user and hides
  # the header from clients).
  #
  # Must sit outside LinkedData::Security::Authorization, which sets
  # REMOTE_USER, and outside Rack::Cache, so a cached response never carries
  # another user's name.
  class ApiUserHeader
    HEADER = 'x-api-user'.freeze

    def initialize(app)
      @app = app
    end

    def call(env)
      status, headers, body = @app.call(env)

      # e.g. "apikey token=<UI key>&userapikey=<user key>" -> the end user
      user = env['REMOTE_USER']
      headers[HEADER] = user.username.to_s if user.respond_to?(:username)

      [status, headers, body]
    end
  end
end

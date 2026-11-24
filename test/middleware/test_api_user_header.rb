require_relative '../test_case'

class TestApiUserHeader < TestCase
  API_USER_HEADER = 'x-api-user'.freeze

  def setup
    @app_user = User.new(username: 'header_app', email: 'header_app@example.org', password: '12345')
    @app_user.save
    @end_user = User.new(username: 'header_end_user', email: 'header_end_user@example.org', password: '12345')
    @end_user.save
  end

  def teardown
    %w[header_app header_end_user].each do |username|
      user = User.find(username).first
      user&.delete
    end
  end

  def test_header_names_the_apikey_user
    with_settings(enable_security: true) do
      get "/categories?apikey=#{@app_user.apikey}"
    end

    assert_equal 'header_app', last_response.headers[API_USER_HEADER]
  end

  def test_header_names_the_end_user_behind_an_app_key
    # The UI sends its own key plus the logged-in user's key
    with_settings(enable_security: true) do
      header 'Authorization', "apikey token=#{@app_user.apikey}&userapikey=#{@end_user.apikey}"
      get '/categories'
    end

    assert_equal 'header_end_user', last_response.headers[API_USER_HEADER]
  end

  def test_no_header_without_apikey
    with_settings(enable_security: true) do
      get '/categories'
    end

    assert_nil last_response.headers[API_USER_HEADER]
  end
end

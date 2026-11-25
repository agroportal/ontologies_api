require_relative 'test_case'

class TestTrailingSlashRedirect < TestCase
  MOVED_PERMANENTLY = 301

  def test_redirect_keeps_query_string
    # e.g. BioMixer calls ".../paths_to_root/?apikey=..."; dropping the query lost the apikey
    get '/categories/?display=name'

    assert_equal MOVED_PERMANENTLY, last_response.status
    assert last_response.location.end_with?('/categories?display=name'), last_response.location
  end

  def test_redirect_without_query_string
    get '/categories/'

    assert_equal MOVED_PERMANENTLY, last_response.status
    assert last_response.location.end_with?('/categories'), last_response.location
  end
end

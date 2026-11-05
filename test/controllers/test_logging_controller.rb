require_relative '../test_case'
require "multi_json"

class TestLoggingController < TestCase

  def setup
    Goo.use_cache = true
    Goo.redis_client.flushdb
    Goo.enable_query_logging(enabled: true, file: "./queries.log")
  end

  def teardown
    Goo.enable_query_logging(enabled: false, file: nil)
    File.delete("./queries.log") if File.exist?("./queries.log")
    Goo.redis_client.flushdb
    Goo.use_cache = false
  end

  def test_logging_endpoint
    (1..10).each do |_i|
      LinkedData::Models::Ontology.where.include(:acronym).all
    end

    get '/admin/latest_day_query_logs?page=1&pagesize=9'
    assert last_response.ok?
    logs = MultiJson.load(last_response.body)
    assert_equal 9, logs['collection'].size

    get '/admin/latest_day_query_logs?page=2&pagesize=9'
    assert last_response.ok?
    logs = MultiJson.load(last_response.body)
    refute_empty logs['collection']

    get '/admin/latest_day_query_logs?page=3&pagesize=9'
    assert last_response.ok?
    logs = MultiJson.load(last_response.body)
    assert_empty logs['collection']
  end

  def test_n_last_seconds_logs
    Goo.logger.info("Test log")
    (1..10).each do |_i|
      LinkedData::Models::Ontology.where.include(:acronym).all
    end

    Goo.logger.info("Test log")
    get '/admin/last_n_s_query_logs?seconds=2&page=1&pagesize=10'
    assert last_response.ok?
    logs = MultiJson.load(last_response.body)
    assert_equal 10, logs['collection'].size

    sleep 1
    LinkedData::Models::Ontology.where.include(:acronym).all
    get '/admin/last_n_s_query_logs?seconds=1&page=1&pagesize=10'
    assert last_response.ok?
    logs = MultiJson.load(last_response.body)
    assert_equal 1, logs['collection'].size
  end
end

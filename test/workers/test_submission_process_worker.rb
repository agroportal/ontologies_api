require_relative '../test_case'
require 'ostruct'
require 'minitest/stub_any_instance'

class TestSubmissionProcessWorker < TestCase
  def teardown
    SubmissionProcessWorker.clear
  end

  def test_transient_error_classification
    assert SubmissionProcessWorker.transient_error?(Errno::ECONNREFUSED.new)
    assert SubmissionProcessWorker.transient_error?(Net::ReadTimeout.new)

    # a transient cause wrapped in a generic error is still detected
    wrapped = begin
      begin
        raise Errno::ECONNRESET
      rescue StandardError
        raise StandardError, 'wrapper around a network failure'
      end
    rescue StandardError => e
      e
    end
    assert SubmissionProcessWorker.transient_error?(wrapped)

    # parse/validation failures are permanent
    refute SubmissionProcessWorker.transient_error?(ArgumentError.new('Submission is missing an ontology file, cannot parse.'))
    refute SubmissionProcessWorker.transient_error?(StandardError.new('OWLAPI parse failure'))
  end

  def test_enqueue_normalizes_actions
    submission = OpenStruct.new(id: RDF::IRI.new('http://data.bioontology.org/ontologies/TST/submissions/1'))

    # all: true wins, unknown keys (like the legacy :params) are dropped
    SubmissionProcessWorker.enqueue(submission, { all: true, params: { 'junk' => 'data' } })
    args = SubmissionProcessWorker.jobs.last['args']
    assert_equal 'http://data.bioontology.org/ontologies/TST/submissions/1', args[0]
    assert_equal({ 'all' => true }, args[1])

    # explicit actions are filtered against the known processing actions
    SubmissionProcessWorker.enqueue(submission, { process_rdf: true, index_search: false, bogus: true })
    assert_equal({ 'process_rdf' => true, 'index_search' => false }, SubmissionProcessWorker.jobs.last['args'][1])
  end

  def test_missing_submission_is_skipped_without_retry
    worker = SubmissionProcessWorker.new
    worker.jid = 'test-jid-missing'
    worker.perform('http://data.bioontology.org/ontologies/NONEXISTENT/submissions/99', 'all' => true)
    assert_empty SubmissionProcessWorker.jobs
  end

  def test_lock_contention_reschedules_the_job
    submission_id = 'http://data.bioontology.org/ontologies/TST/submissions/2'
    lock_key = "locks:submission_process:#{submission_id}"
    Sidekiq.redis { |redis| redis.call('SET', lock_key, 'other-jid', 'EX', 60) }

    worker = SubmissionProcessWorker.new
    worker.jid = 'test-jid-lock'
    worker.perform(submission_id, 'all' => true)

    rescheduled = SubmissionProcessWorker.jobs.last
    refute_nil rescheduled, 'expected the job to reschedule itself'
    assert rescheduled['at'], 'expected a scheduled (delayed) job'
    assert_equal submission_id, rescheduled['args'][0]
    # the other worker's lock was not touched
    assert_equal 'other-jid', Sidekiq.redis { |redis| redis.call('GET', lock_key) }
  ensure
    Sidekiq.redis { |redis| redis.call('DEL', lock_key) }
  end

  def test_permanent_failure_is_wrapped_and_lock_released
    _, _, onts = create_ontologies_and_submissions(ont_count: 1, submission_count: 1, process_submission: false)
    submission = onts.first.latest_submission(status: :any)
    submission_id = submission.id.to_s
    lock_key = "locks:submission_process:#{submission_id}"

    worker = SubmissionProcessWorker.new
    worker.jid = 'test-jid-permanent'

    NcboCron::Models::OntologySubmissionParser.stub_any_instance(:process_submission, ->(*) { raise ArgumentError, 'broken file' }) do
      error = assert_raises(SubmissionProcessWorker::PermanentSubmissionError) do
        worker.perform(submission_id, 'all' => true)
      end
      assert_match(/ArgumentError: broken file/, error.message)
    end
    assert_nil Sidekiq.redis { |redis| redis.call('GET', lock_key) }, 'lock must be released on failure'

    NcboCron::Models::OntologySubmissionParser.stub_any_instance(:process_submission, ->(*) { raise Errno::ECONNREFUSED }) do
      assert_raises(Errno::ECONNREFUSED) do
        worker.perform(submission_id, 'all' => true)
      end
    end
    assert_nil Sidekiq.redis { |redis| redis.call('GET', lock_key) }, 'lock must be released on failure'
  end
end

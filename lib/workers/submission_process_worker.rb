require 'sidekiq'

##
# Processes an ontology submission asynchronously: parsing, indexing, metrics,
# annotator cache, archiving of older submissions and report refresh, by
# delegating to the same ncbo_cron orchestration the cron daemon uses
# (NcboCron::Models::OntologySubmissionParser#process_submission).
class SubmissionProcessWorker
  include Sidekiq::Job

  sidekiq_options queue: 'parsing', retry: 4

  # Raised when a failure cannot be fixed by retrying (invalid submission,
  # broken/unsupported ontology file, missing upload, unreachable pull URL).
  # Sent straight to the Dead set: visible in the Web UI, manually retryable.
  class PermanentSubmissionError < StandardError; end

  LOCK_TTL = 24 * 60 * 60 # seconds; large ontologies can parse for hours
  LOCK_RETRY_DELAY = 10 * 60 # seconds to wait when the submission is locked

  # Errors worth retrying: a backend (Virtuoso/4store, Solr, Redis, mgrep,
  # remote pull host) was unreachable or timed out. Anything else is treated
  # as permanent — retrying a parse of a broken file only reproduces the same
  # ERROR_* submission status.
  TRANSIENT_ERRORS = [
    Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EHOSTUNREACH, Errno::ETIMEDOUT,
    Errno::EPIPE, SocketError, EOFError, Timeout::Error,
    Net::OpenTimeout, Net::ReadTimeout, Net::HTTPBadResponse, OpenSSL::SSL::SSLError
  ].freeze

  # Backend client errors referenced by name: their gems define them lazily or
  # may be absent from a given deployment.
  TRANSIENT_ERROR_NAMES = %w[
    Redis::BaseConnectionError RedisClient::ConnectionError RedisClient::TimeoutError
    Net::HTTP::Persistent::Error RestClient::Exceptions::Timeout RestClient::ServerBrokeConnection
    SPARQL::Client::ServerError Faraday::ConnectionFailed Faraday::TimeoutError
  ].freeze

  sidekiq_retry_in do |_count, exception|
    # :kill sends the job to the Dead set without further retries
    :kill if exception.is_a?(PermanentSubmissionError)
  end

  sidekiq_retries_exhausted do |job, exception|
    Sidekiq.logger.error "Submission processing exhausted its retries, job moved to the Dead set: " \
                         "args=#{job['args'].inspect} (#{exception.class}: #{exception.message})"
  end

  ##
  # Enqueue helper used by the API controllers. Mirrors the legacy
  # NcboCron::Helpers::OntologyHelper.queue_submission contract: `all: true`
  # expands to every processing action, unknown keys (e.g. :params, which the
  # legacy queue silently dropped too) are discarded.
  def self.enqueue(submission, actions = { all: true })
    safe_actions = actions.transform_keys(&:to_s).select do |key, value|
      (key == 'all' || NcboCron::Models::OntologySubmissionParser::ACTIONS.key?(key.to_sym)) &&
        [true, false].include?(value)
    end
    perform_async(submission.id.to_s, safe_actions)
  end

  def perform(submission_id, raw_actions = { 'all' => true })
    actions = normalize_actions(raw_actions)
    return if actions.empty?

    lock_id = submission_id
    unless acquire_lock(lock_id)
      logger.info "Submission #{submission_id} is already being processed, will retry in #{LOCK_RETRY_DELAY}s"
      self.class.perform_in(LOCK_RETRY_DELAY, submission_id, actions.transform_keys(&:to_s))
      return
    end

    begin
      submission_id = pull_remote_submission(submission_id) if actions.delete(:remote_pull)
      return if submission_id.nil?

      submission = LinkedData::Models::OntologySubmission.find(RDF::IRI.new(submission_id)).first
      if submission.nil?
        logger.error "Submission #{submission_id} no longer exists, nothing to process"
        return
      end
      if submission.archived? && !actions[:archive]
        logger.warn "Submission #{submission_id} is archived, skipping processing"
        return
      end

      NcboCron::Models::OntologySubmissionParser.new.process_submission(logger, submission_id, actions)
    rescue StandardError => e
      raise if self.class.transient_error?(e)

      permanent = PermanentSubmissionError.new("#{e.class}: #{e.message}")
      permanent.set_backtrace(e.backtrace)
      raise permanent
    ensure
      release_lock(lock_id)
    end
  end

  def self.transient_error?(error)
    transient_classes = TRANSIENT_ERRORS + TRANSIENT_ERROR_NAMES.filter_map do |name|
      name.split('::').reduce(Object) { |mod, part| mod.const_get(part) }
    rescue NameError
      nil
    end

    # Walk the cause chain: backend failures often surface wrapped in
    # higher-level exceptions.
    chain = []
    current = error
    while current && !chain.include?(current)
      chain << current
      current = current.cause
    end
    chain.any? { |ex| transient_classes.any? { |klass| ex.is_a?(klass) } }
  end

  private

  def normalize_actions(raw_actions)
    actions = raw_actions.transform_keys(&:to_sym)
    return NcboCron::Models::OntologySubmissionParser::ACTIONS.dup if actions[:all]

    actions.select do |key, value|
      NcboCron::Models::OntologySubmissionParser::ACTIONS.key?(key) && [true, false].include?(value)
    end
  end

  # POST /ontologies/:acronym/pull and the admin reprocess endpoint enqueue
  # `remote_pull: true`: download a fresh copy of the ontology first, then
  # process the newly created submission (same branch the cron queue had).
  def pull_remote_submission(submission_id)
    acronym = NcboCron::Helpers::OntologyHelper.acronym_from_submission_id(submission_id)
    new_submission = NcboCron::Helpers::OntologyHelper.do_ontology_pull(acronym,
                                                                        enable_pull_umls: false,
                                                                        umls_download_url: '',
                                                                        logger: logger,
                                                                        add_to_queue: false)
    if new_submission.nil?
      logger.info "Remote pull for #{acronym} produced no new submission (remote file unchanged), nothing to process"
      return nil
    end
    new_submission.id.to_s
  end

  def acquire_lock(submission_id)
    Sidekiq.redis { |redis| redis.call('SET', lock_key(submission_id), jid, 'NX', 'EX', LOCK_TTL) }
  end

  def release_lock(submission_id)
    Sidekiq.redis do |redis|
      key = lock_key(submission_id)
      redis.call('DEL', key) if redis.call('GET', key) == jid
    end
  end

  def lock_key(submission_id)
    "locks:submission_process:#{submission_id}"
  end
end

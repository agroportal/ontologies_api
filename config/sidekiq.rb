require 'sidekiq'

# Sidekiq uses its own Redis database, separate from the goo/http/annotator
# caches (see docker-compose.yml redis-ut). Point REDIS_SIDEKIQ_* at a
# persistent Redis instance in production: queued/retrying/dead jobs and all
# Sidekiq stats live only in this database and are lost if it is wiped.
sidekiq_redis_host = ENV['REDIS_SIDEKIQ_HOST'] || 'localhost'
sidekiq_redis_port = ENV['REDIS_SIDEKIQ_PORT'] || '6379'
sidekiq_redis_db   = ENV['REDIS_SIDEKIQ_DB'] || '10'
SIDEKIQ_REDIS_URL = "redis://#{sidekiq_redis_host}:#{sidekiq_redis_port}/#{sidekiq_redis_db}".freeze

# Client side (web process): connections are created lazily on the first
# perform_async, so this is fork-safe under unicorn's preload_app.
Sidekiq.configure_client do |config|
  config.redis = { url: SIDEKIQ_REDIS_URL }
end

Sidekiq.configure_server do |config|
  config.redis = { url: SIDEKIQ_REDIS_URL }

  # The default capsule (concurrency/queues from config/sidekiq.yml) runs the
  # lightweight `default` and `mailers` queues. Ontology processing runs in
  # its own capsule so heavy parse jobs (each spawns an OWLAPI java
  # subprocess) never occupy more than SIDEKIQ_PARSING_CONCURRENCY threads,
  # mirroring the serial processing the ncbo_cron daemon enforced with its
  # global lock.
  config.capsule('heavy') do |capsule|
    capsule.queues = %w[parsing]
    capsule.concurrency = (ENV['SIDEKIQ_PARSING_CONCURRENCY'] || 1).to_i
  end
end

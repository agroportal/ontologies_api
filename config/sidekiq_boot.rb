# Entry point for the Sidekiq worker process:
#   bundle exec sidekiq -r ./config/sidekiq_boot.rb -C config/sidekiq.yml
#
# Requiring app.rb boots the worker exactly like the web process: same gems
# (ontologies_linked_data, ncbo_cron, annotator — including bundler local
# path overrides), same config/config.rb, same environment file and
# OVERRIDE_CONFIG handling, and the same lib/ tree (workers, Notifier patch).
# Sinatra will not start its own HTTP server here because app.rb is not $0.
require_relative '../app'

Sidekiq.logger.info "ontologies_api booted for Sidekiq " \
                    "(env: #{Sinatra::Application.settings.environment}, redis: #{SIDEKIQ_REDIS_URL})"

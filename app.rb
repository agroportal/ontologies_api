$VERBOSE = false

# sinatra-base
require 'sinatra'

# sinatra-contrib
require 'sinatra/respond_with'
require 'sinatra/namespace'
require 'sinatra/multi_route'

# Other gem dependencies
require 'oj'
require 'multi_json'
require 'cgi'

# NCBO dependencies
require 'ontologies_linked_data'
require 'ncbo_annotator'
require 'ncbo_cron'
require 'ncbo_ontology_recommender'

# Require middleware
require 'rack/accept'
require 'rack/post-body-to-params'
require 'rack-timeout'
require 'rack/cors'
require_relative 'lib/rack/slow_requests'
require_relative 'lib/rack/param_translator'
require_relative 'lib/rack/slice_detection'
require_relative 'lib/rack/request_lang'

# Logging setup
require_relative 'config/logging'

# Inflector setup
require_relative 'config/inflections'

require 'request_store'

# Protection settings
set :protection, except: :path_traversal

# Allow HTTP method overrides
set :method_override, true

# Setup root and static public directory
set :root, File.dirname(__FILE__)

require 'rack/contrib'
use Rack::Static,
    urls: ['/static'],
    root: 'public'
set :public_folder, File.expand_path('public', __dir__)
set :static, true

# Setup the environment
environment = settings.environment.nil? ? :development : settings.environment
require_relative 'config/config'

if ENV['OVERRIDE_CONFIG'] == 'true'
  LinkedData.config do |config|
    config.goo_backend_name = ENV['GOO_BACKEND_NAME']
    config.goo_host = ENV['GOO_HOST']
    config.goo_port = ENV['GOO_PORT'].to_i
    config.goo_path_query = ENV['GOO_PATH_QUERY']
    config.goo_path_data = ENV['GOO_PATH_DATA']
    config.goo_path_update = ENV['GOO_PATH_UPDATE']
    config.goo_redis_host = ENV['REDIS_HOST']
    config.goo_redis_port = ENV['REDIS_PORT']
    config.http_redis_host = ENV['REDIS_HOST']
    config.http_redis_port = ENV['REDIS_PORT']
  end

  Annotator.config do |config|
    config.annotator_redis_host = ENV['ANNOTATOR_REDIS_HOST']
    config.annotator_redis_port = ENV['ANNOTATOR_REDIS_PORT']
    config.mgrep_host = ENV['MGREP_HOST']
    config.mgrep_port = ENV['MGREP_PORT']
  end
end

require_relative "config/environments/#{environment}.rb"

# Sidekiq client/server configuration (background jobs)
require_relative 'config/sidekiq'

# Development-specific options
if [:development, :console].include?(settings.environment)
  require 'pry' # Debug by placing 'binding.pry' where you want the interactive console to start
  # Show exceptions
  set :raise_errors, true
  set :dump_errors, false
  set :show_exceptions, false
  # use Rack::DowncaseHeaders to ensure headers are downcased for rack > 3.0 compatibility
  require_relative 'lib/rack/downcase_headers'
  use Rack::DowncaseHeaders
end

use Rack::Cors do
  allow do
    origins '*'
    resource '*', headers: :any, methods: [:get, :post, :put, :patch, :delete, :options]
  end
end

# Show exceptions after timeout
if LinkedData::OntologiesAPI.settings.enable_req_timeout
  use Rack::Timeout; Rack::Timeout.timeout = LinkedData::OntologiesAPI.settings.req_timeout # seconds, shorter than unicorn timeout
end

use Rack::SliceDetection
use Rack::Accept
use Rack::PostBodyToParams
use Rack::ParamTranslator

use RequestStore::Middleware
use Rack::RequestLang

use LinkedData::Security::Authorization
use LinkedData::Security::AccessDenied

if LinkedData::OntologiesAPI.settings.enable_throttling
  require_relative 'config/rack_attack'
end

if LinkedData.settings.enable_http_cache
  require 'rack/cache'
  require 'redis-rack-cache'
  redis_host_port = "#{LinkedData::OntologiesAPI.settings.http_redis_host}:#{LinkedData::OntologiesAPI.settings.http_redis_port}"
  verbose = environment == :development
  use Rack::Cache,
      verbose: verbose,
      allow_reload: true,
      metastore: "redis://#{redis_host_port}/0/metastore",
      entitystore: "redis://#{redis_host_port}/0/entitystore"
end

# Initialize unicorn Worker killer to mitigate unicorn worker memory bloat
if LinkedData::OntologiesAPI.settings.enable_unicorn_workerkiller
  require 'unicorn'
  require_relative 'config/unicorn_workerkiller'
end

if $SENTRY_DSN
  require 'sentry-ruby'
  Sentry.init do |config|
    config.dsn = $SENTRY_DSN

    # Add data like request headers and IP for users,
    # see https://docs.sentry.io/platforms/ruby/data-management/data-collected/ for more info
    config.send_default_pii = true
  end

  # use Rack::RewindableInput::Middleware
  use Sentry::Rack::CaptureExceptions
end

# Initialize the app
require_relative 'init'

# Enter console mode
if settings.environment == :console
  require 'rack/test'
  include Rack::Test::Methods;

  def app()
    Sinatra::Application
  end

  Pry.start binding, quiet: true
  exit
end

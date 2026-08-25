require './app.rb'

apps = { '/' => Sinatra::Application }

# Sidekiq Web UI, only mounted when credentials are configured
if !ENV['SIDEKIQ_WEB_USER'].to_s.empty? && !ENV['SIDEKIQ_WEB_PASSWORD'].to_s.empty?
  require 'securerandom'
  require 'rack/session'
  require 'sidekiq/web'

  Sidekiq::Web.use Rack::Session::Cookie,
                   secret: ENV['SIDEKIQ_WEB_SESSION_SECRET'] || SecureRandom.hex(64),
                   same_site: true,
                   max_age: 86_400
  Sidekiq::Web.use Rack::Auth::Basic, 'Sidekiq' do |user, password|
    Rack::Utils.secure_compare(user, ENV['SIDEKIQ_WEB_USER']) &
      Rack::Utils.secure_compare(password, ENV['SIDEKIQ_WEB_PASSWORD'])
  end

  apps['/sidekiq'] = Sidekiq::Web
end

run Rack::URLMap.new(apps)

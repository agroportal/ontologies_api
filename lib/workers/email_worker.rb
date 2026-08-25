require 'sidekiq'

##
# Delivers one notification email over SMTP. Enqueued by the AsyncNotifier
# patch (lib/utils/notifier_async.rb) with the already-resolved, primitive
# notify options (recipients/subject/body/sender strings).
class EmailWorker
  include Sidekiq::Job

  sidekiq_options queue: 'mailers', retry: 5

  def perform(options)
    notify_options = options.transform_keys(&:to_sym)
    notify_options[:sync] = true # bypass the AsyncNotifier patch and actually send
    LinkedData::Utils::Notifier.notify(notify_options)
  end
end

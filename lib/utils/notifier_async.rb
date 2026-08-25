##
# Routes every LinkedData email notification (submission processed, notes,
# user creation, support mails, ...) through the Sidekiq `mailers` queue
# instead of blocking the caller on a synchronous SMTP delivery.
#
# The patch sits on the lowest-level seam, LinkedData::Utils::Notifier.notify,
# so recipient resolution (e.g. notify_subscribed_separately) still happens in
# the caller and only the SMTP call goes async. EmailWorker calls back with
# `sync: true` to reach the original implementation.
module LinkedData
  module Utils
    module AsyncNotifier
      def notify(options = {})
        return super if options[:sync]
        return super unless LinkedData.settings.enable_notifications
        # Preserve the synchronous ArgumentError raised for missing recipients
        return super if Array(options[:recipients]).uniq.empty?

        EmailWorker.perform_async(options.transform_keys(&:to_s))
      end
    end

    Notifier.singleton_class.prepend(AsyncNotifier)
  end
end

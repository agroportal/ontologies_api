require_relative '../test_case'

class TestEmailWorker < AppUnit
  def setup
    EmailWorker.clear
    @original_enable = LinkedData.settings.enable_notifications
    @original_disable_override = LinkedData.settings.email_disable_override
  end

  def teardown
    LinkedData.settings.enable_notifications = @original_enable
    LinkedData.settings.email_disable_override = @original_disable_override
    EmailWorker.clear
  end

  def test_notify_enqueues_instead_of_sending
    LinkedData.settings.enable_notifications = true
    LinkedData::Utils::Notifier.notify(recipients: 'someone@example.org', subject: 'Hi', body: 'Test body')

    assert_equal 1, EmailWorker.jobs.size
    options = EmailWorker.jobs.last['args'].first
    assert_equal 'someone@example.org', options['recipients']
    assert_equal 'Hi', options['subject']
    assert_equal 'Test body', options['body']
  end

  def test_worker_delivers_via_pony_without_re_enqueueing
    LinkedData.settings.enable_notifications = true
    LinkedData.settings.email_disable_override = true # deliver to the actual recipients

    delivered = []
    Pony.stub :mail, ->(opts) { delivered << opts } do
      EmailWorker.new.perform('recipients' => 'someone@example.org', 'subject' => 'Hi', 'body' => 'Test body')
    end

    assert_equal 1, delivered.size
    assert_equal ['someone@example.org'], delivered.first[:to]
    assert_equal 'Hi', delivered.first[:subject]
    assert_empty EmailWorker.jobs, 'sync delivery must not enqueue another job'
  end

  def test_disabled_notifications_do_not_enqueue
    LinkedData.settings.enable_notifications = false
    result = LinkedData::Utils::Notifier.notify(recipients: 'someone@example.org', subject: 'Hi', body: 'Test body')
    assert_nil result
    assert_empty EmailWorker.jobs
  end

  def test_missing_recipients_raise_synchronously
    LinkedData.settings.enable_notifications = true
    assert_raises(ArgumentError) do
      LinkedData::Utils::Notifier.notify(subject: 'Hi', body: 'Test body')
    end
    assert_empty EmailWorker.jobs
  end
end

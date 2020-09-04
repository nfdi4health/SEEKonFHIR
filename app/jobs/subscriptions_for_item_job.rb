# abstract superclass for common methods for handling subscription items, common to SetSubcriptionsForItemJob
# and RemoveSubscriptionForItemJob.
# perform_job methods is implemented in those subclasses
class SubscriptionsForItemJob < SeekJob
  queue_with_priority 1

  before_perform do
    # make sure the SMTP,site_base_host configuration is in sync with current SEEK settings
    Seek::Config.smtp_propagate
    Seek::Config.site_base_host_propagate
  end

  def perform(subscribable, projects)
    # do something
  end
end

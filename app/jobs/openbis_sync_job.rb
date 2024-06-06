# job to periodically take OBIS assets that are due to synchronization
# and refresh their content with the current state in OBIS
# It can also follow the dependent Objects/DataSets and register them if so configured
class OpenbisSyncJob < BatchJob
  queue_with_priority 3

  # debug is with puts so it can be easily seen on tests screens
  DEBUG = Seek::Config.openbis_debug ? true : false
  BATCH_SIZE = 20

  def perform(*args)
    return unless Seek::Config.openbis_enabled
    return unless endpoint&.persisted?
    super.tap { endpoint.touch(:last_sync) }
  end

  def perform_job(obis_asset)
    if DEBUG
      puts "starting obis sync of #{obis_asset.class}:#{obis_asset.id} perm_id: #{obis_asset.external_id}"
      Rails.logger.info "starting obis sync of #{obis_asset.class}:#{obis_asset.id} perm_id: #{obis_asset.external_id} #{obis_asset.external_type}"
    end

    errs = []
    obis_asset.reload

    begin

      # current user is being set to asset creator (it will be registered on his behalf)
      # maybe it should be done by a system user instead???

      User.with_current_user(obis_asset.seek_entity.contributor.user) do
        errs = seek_util.sync_external_asset(obis_asset) unless obis_asset.synchronized?
      end

    rescue Exception => e
      Rails.logger.error "Unrecovered ERROR in syn job #{e.message} #{e.backtrace.join("\n\t")}"
      raise e
    end

    if obis_asset.failed?
      handle_sync_failure obis_asset
    else
      # always touch asset so its updated_at stamp is modified as it is used for queuing entiries
      obis_asset.touch
    end

    print_sync_status(obis_asset, errs)
  end

  def handle_sync_failure(obis_asset)
    return if obis_asset.failures <= failure_threshold

    obis_asset.sync_state = :fatal
    obis_asset.err_msg = 'Stopped sync: ' + obis_asset.err_msg
    obis_asset.save
    Rails.logger.error "Marked OBisAsset:#{obis_asset.id} perm_id: #{obis_asset.external_id} as fatal no more sync"
  end

  def print_sync_status(obis_asset, errs)
    if errs.empty?
      Rails.logger.info "successful obis sync of OBisAsset:#{obis_asset.id} perm_id: #{obis_asset.external_id}" if DEBUG
    else
      msg = "Sync issues with OBisAsset:#{obis_asset.id} perm_id: #{obis_asset.external_id}\n#{errs.join(',\n')}"
      puts msg if DEBUG
      Rails.logger.error msg
    end
  end

  def gather_items
    need_sync.to_a
  end

  def need_sync
    # bussines rule
    # - status refresh or failed
    # - synchronized_at before (Now - endpoint refresh)
    # - for failed: last update before (Now - endpoint_refresh/2) to prevent constant checking of failed entries)
    # - fatal not returned

    service = endpoint # to prevent multiple calls

    old = DateTime.now - service.refresh_period_mins.minutes
    too_fresh = DateTime.now - (service.refresh_period_mins / 2).minutes

    service.external_assets
        .where('synchronized_at < ? AND (sync_state = ? OR (updated_at < ? AND sync_state =?))',
               old, ExternalAsset.sync_states[:refresh], too_fresh, ExternalAsset.sync_states[:failed])
        .order(:sync_state, :updated_at)
        .limit(batch_size)
  end

  def failure_threshold
    t = (2.days / endpoint.refresh_period_mins.minutes).to_i
    t < 3 ? 3 : t
  end

  # jobs created if due, triggered by the scheduler.rb
  def self.queue_timed_jobs
    return unless Seek::Config.openbis_enabled && Seek::Config.openbis_autosync
    OpenbisEndpoint.find_each do |endpoint|
      endpoint.create_sync_metadata_job if endpoint.due_sync?
    end
  end

  def seek_util
    # looks like local variables are wrote to yaml and becomes job parameter
    # @seek_util ||= Seek::Openbis::SeekUtil.new
    Seek::Openbis::SeekUtil.new
  end

  def follow_on_job?
    endpoint&.persisted? && need_sync.any?
  end

  private

  def batch_size
    arguments[1] || BATCH_SIZE
  end

  def endpoint
    arguments[0]
  end
end

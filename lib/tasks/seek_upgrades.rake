# frozen_string_literal: true

require 'rubygems'
require 'rake'


namespace :seek do
  # these are the tasks required for this version upgrade
  task upgrade_version_tasks: %i[
    environment
    db:seed:010_workflow_classes
    db:seed:011_edam_topics
    db:seed:012_edam_operations   
    db:seed:013_workflow_data_file_relationships
    rename_branding_settings
    update_missing_openbis_istest
  ]

  # these are the tasks that are executes for each upgrade as standard, and rarely change
  task standard_upgrade_tasks: %i[
    environment
    clear_filestore_tmp
    repopulate_auth_lookup_tables
  ]

  desc('upgrades SEEK from the last released version to the latest released version')
  task(upgrade: [:environment]) do
    puts "Starting upgrade ..."
    puts "... trimming old session data ..."
    Rake::Task['db:sessions:trim'].invoke
    puts "... migrating database ..."
    Rake::Task['db:migrate'].invoke
    Rake::Task['tmp:clear'].invoke

    solr = Seek::Config.solr_enabled
    Seek::Config.solr_enabled = false

    begin
      puts "... performing upgrade tasks ..."
      Rake::Task['seek:standard_upgrade_tasks'].invoke
      Rake::Task['seek:upgrade_version_tasks'].invoke

      Seek::Config.solr_enabled = solr
      puts "... queuing search reindexing jobs ..."
      Rake::Task['seek:reindex_all'].invoke if solr

      puts 'Upgrade completed successfully'
    ensure
      Seek::Config.solr_enabled = solr
    end
  end

  task(rename_branding_settings: [:environment]) do
    Seek::Config.transfer_value :project_link, :instance_link
    Seek::Config.transfer_value :project_name, :instance_name
    Seek::Config.transfer_value :project_description, :instance_description
    Seek::Config.transfer_value :project_keywords, :instance_keywords

    Seek::Config.transfer_value :dm_project_name, :instance_admins_name
    Seek::Config.transfer_value :dm_project_link, :instance_admins_link
  end

  task(update_missing_openbis_istest: :environment) do
    puts '... creating missing is_test for OpenbisEndpoint...'
    create = 0
    disable_authorization_checks do
      OpenbisEndpoint.find_each do |openbis_endpoint|
        # check if the publication has a version
        # then create one if missing
        if openbis_endpoint.is_test.nil?
          openbis_endpoint.is_test = false # default -> prod, https
          openbis_endpoint.save
          unless openbis_endpoint.is_test.nil?
            create += 1
          end
        end
        # publication.save
      end
    end
    puts " ... finished creating missing is_test for #{create.to_s} OpenbisEndpoint(s)"
  end

end

# frozen_string_literal: true

namespace :ruby_llm_agents do
  desc "Validate your RubyLLM::Agents setup (API keys, migrations, routes, jobs)"
  task doctor: :environment do
    require "generators/ruby_llm_agents/doctor_generator"
    RubyLlmAgents::DoctorGenerator.start([])
  end

  desc "Run the retention job synchronously (soft + hard purges per configuration)"
  task purge: :environment do
    result = RubyLLM::Agents::RetentionJob.new.perform
    puts "Soft purged: #{result[:soft_purged]} executions (details destroyed)"
    puts "Hard purged: #{result[:hard_purged]} executions (rows destroyed)"
  end

  desc "Rename an agent type in execution records. Usage: rake ruby_llm_agents:rename_agent FROM=OldName TO=NewName [DRY_RUN=1]"
  task rename_agent: :environment do
    from = ENV["FROM"]
    to = ENV["TO"]
    dry_run = ENV["DRY_RUN"] == "1"

    abort "Usage: rake ruby_llm_agents:rename_agent FROM=OldAgentName TO=NewAgentName [DRY_RUN=1]" unless from && to

    result = RubyLLM::Agents.rename_agent(from, to: to, dry_run: dry_run)

    if dry_run
      puts "Dry run results:"
      puts "  Executions affected: #{result[:executions_affected]}"
      puts "  Tenants affected:    #{result[:tenants_affected]}"
    else
      puts "Rename complete:"
      puts "  Executions updated: #{result[:executions_updated]}"
      puts "  Tenants updated:    #{result[:tenants_updated]}"
    end
  end

  namespace :tenants do
    desc "Refresh all tenant counters from executions table"
    task refresh: :environment do
      count = 0
      RubyLLM::Agents::Tenant.find_each do |tenant|
        tenant.refresh_counters!
        count += 1
      end
      puts "Refreshed #{count} tenants"
    end

    desc "Refresh active tenant counters from executions table"
    task refresh_active: :environment do
      count = 0
      RubyLLM::Agents::Tenant.active.find_each do |tenant|
        tenant.refresh_counters!
        count += 1
      end
      puts "Refreshed #{count} active tenants"
    end

    desc "Refresh a single tenant's counters"
    task :refresh_one, [:tenant_id] => :environment do |_, args|
      abort "Usage: rake ruby_llm_agents:tenants:refresh_one[tenant_id]" unless args[:tenant_id]

      tenant = RubyLLM::Agents::Tenant.find_by!(tenant_id: args[:tenant_id])
      tenant.refresh_counters!
      puts "Refreshed tenant: #{tenant.tenant_id}"
    end
  end
end

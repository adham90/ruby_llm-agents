# frozen_string_literal: true

namespace :ruby_llm_agents do
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

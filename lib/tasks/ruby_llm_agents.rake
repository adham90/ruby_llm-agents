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

  desc "Redact credential-shaped keys from historical execution metadata. Usage: rake ruby_llm_agents:redact_metadata_secrets [DRY_RUN=1]"
  task redact_metadata_secrets: :environment do
    # Versions before the tenant-API-key fix wrote per-tenant provider keys into
    # executions.metadata in plaintext, and the execution page renders that
    # column verbatim. New rows are safe; this scrubs the ones already written.
    #
    # Rotate the affected keys as well — redacting the copy in the database does
    # not un-expose a key that was already displayed.
    dry_run = ENV["DRY_RUN"].present?
    pattern = RubyLLM::Agents::Pipeline::Middleware::Instrumentation::SECRET_METADATA_PATTERN
    scanned = 0
    redacted = 0

    RubyLLM::Agents::Execution.where.not(metadata: nil).find_each do |execution|
      scanned += 1
      metadata = execution.metadata
      next unless metadata.is_a?(Hash)

      offending = metadata.keys.select { |key| key.to_s.match?(pattern) }
      next if offending.empty?

      redacted += 1
      puts "execution ##{execution.id}: #{offending.join(", ")}"
      next if dry_run

      execution.update_column(
        :metadata,
        metadata.merge(offending.to_h { |key| [key, "[REDACTED]"] })
      )
    end

    puts dry_run ? "DRY RUN — #{redacted} of #{scanned} executions would be redacted" : "Redacted #{redacted} of #{scanned} executions"
    puts "Rotate any exposed credential: redaction here does not un-expose it." if redacted.positive?
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

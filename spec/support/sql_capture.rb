# frozen_string_literal: true

# Collects the SQL statements executed inside a block.
#
# Used by the dashboard performance regressions to assert on query count and
# shape (no duplicate aggregates, no SELECT * of the detail table, and so on).
# Schema and transaction statements are excluded.
module SqlCapture
  def capture_sql
    statements = []
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      statements << payload[:sql] unless /SCHEMA|TRANSACTION/.match?(payload[:name].to_s)
    end
    yield
    statements
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end
end

RSpec.configure do |config|
  config.include SqlCapture
end

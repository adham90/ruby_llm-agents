# frozen_string_literal: true

module RubyLLM
  module Agents
    class Workflow
      module DSL
        # Helper methods for scheduling wait_until time calculations
        #
        # These methods can be used within workflow definitions to create
        # dynamic scheduling logic for wait_until time: expressions.
        #
        # @example Using in a workflow
        #   class ReportWorkflow < RubyLLM::Agents::Workflow
        #     include ScheduleHelpers
        #
        #     step :generate, ReportAgent
        #     wait_until time: -> { next_weekday_at(9, 0) }
        #     step :send, EmailAgent
        #   end
        #
        # @api public
        module ScheduleHelpers
          # Returns the next occurrence of a weekday (Mon-Fri) at the specified time
          #
          # @param hour [Integer] Hour (0-23)
          # @param minute [Integer] Minute (0-59)
          # @param timezone [String, nil] Timezone name (uses system timezone if nil)
          # @return [Time]
          def next_weekday_at(hour, minute, timezone: nil)
            now = current_time(timezone)
            target = build_time(now, hour, minute, timezone)

            # If target time has passed today or it's a weekend, find next weekday
            if target <= now || weekend?(target)
              target = advance_to_next_weekday(target)
            end

            target
          end

          # Returns the start of the next hour
          #
          # @param timezone [String, nil] Timezone name
          # @return [Time]
          def next_hour(timezone: nil)
            now = current_time(timezone)
            Time.new(now.year, now.month, now.day, now.hour + 1, 0, 0, now.utc_offset)
          end

          # Returns tomorrow at the specified time
          #
          # @param hour [Integer] Hour (0-23)
          # @param minute [Integer] Minute (0-59)
          # @param timezone [String, nil] Timezone name
          # @return [Time]
          def tomorrow_at(hour, minute, timezone: nil)
            now = current_time(timezone)
            tomorrow = now + 86_400 # Add one day in seconds
            build_time(tomorrow, hour, minute, timezone)
          end

          # Returns the next available time within business hours
          #
          # Business hours default to Mon-Fri, 9am-5pm.
          #
          # @param start_hour [Integer] Business day start hour (default: 9)
          # @param end_hour [Integer] Business day end hour (default: 17)
          # @param timezone [String, nil] Timezone name
          # @return [Time]
          def in_business_hours(start_hour: 9, end_hour: 17, timezone: nil)
            now = current_time(timezone)

            # If current time is within business hours, return now
            if within_business_hours?(now, start_hour, end_hour)
              return now
            end

            # If before business hours today and it's a weekday
            if now.hour < start_hour && !weekend?(now)
              return build_time(now, start_hour, 0, timezone)
            end

            # Find next business day
            target = next_weekday_at(start_hour, 0, timezone: timezone)
            target
          end

          # Returns a specific day of the week at the specified time
          #
          # @param day [Symbol] Day name (:monday, :tuesday, etc.)
          # @param hour [Integer] Hour (0-23)
          # @param minute [Integer] Minute (0-59)
          # @param timezone [String, nil] Timezone name
          # @return [Time]
          def next_day_at(day, hour, minute, timezone: nil)
            days = %i[sunday monday tuesday wednesday thursday friday saturday]
            target_wday = days.index(day.to_sym)
            raise ArgumentError, "Unknown day: #{day}" unless target_wday

            now = current_time(timezone)
            current_wday = now.wday
            days_ahead = (target_wday - current_wday) % 7

            # If it's the same day but time has passed, add a week
            if days_ahead == 0
              target = build_time(now, hour, minute, timezone)
              days_ahead = 7 if target <= now
            end

            future = now + (days_ahead * 86_400)
            build_time(future, hour, minute, timezone)
          end

          # Returns time at the start of the next month
          #
          # @param day [Integer] Day of month (default: 1)
          # @param hour [Integer] Hour (default: 0)
          # @param minute [Integer] Minute (default: 0)
          # @param timezone [String, nil] Timezone name
          # @return [Time]
          def next_month_at(day: 1, hour: 0, minute: 0, timezone: nil)
            now = current_time(timezone)
            year = now.year
            month = now.month + 1

            if month > 12
              month = 1
              year += 1
            end

            Time.new(year, month, day, hour, minute, 0, now.utc_offset)
          end

          # Returns a time offset from now
          #
          # @param seconds [Integer, Float] Seconds to add
          # @param timezone [String, nil] Timezone name
          # @return [Time]
          def from_now(seconds, timezone: nil)
            current_time(timezone) + seconds
          end

          private

          def current_time(timezone)
            if timezone && defined?(ActiveSupport::TimeZone)
              ActiveSupport::TimeZone[timezone]&.now || Time.now
            else
              Time.now
            end
          end

          def build_time(base, hour, minute, timezone)
            if timezone && defined?(ActiveSupport::TimeZone)
              zone = ActiveSupport::TimeZone[timezone]
              if zone
                zone.local(base.year, base.month, base.day, hour, minute, 0)
              else
                Time.new(base.year, base.month, base.day, hour, minute, 0, base.utc_offset)
              end
            else
              Time.new(base.year, base.month, base.day, hour, minute, 0, base.utc_offset)
            end
          end

          def weekend?(time)
            time.saturday? || time.sunday?
          end

          def advance_to_next_weekday(time)
            loop do
              time += 86_400 # Add one day
              break unless weekend?(time)
            end
            time
          end

          def within_business_hours?(time, start_hour, end_hour)
            !weekend?(time) &&
              time.hour >= start_hour &&
              time.hour < end_hour
          end
        end
      end
    end
  end
end

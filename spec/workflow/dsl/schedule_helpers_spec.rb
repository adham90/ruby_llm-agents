# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Workflow::DSL::ScheduleHelpers do
  let(:helper_class) do
    Class.new do
      include RubyLLM::Agents::Workflow::DSL::ScheduleHelpers
    end
  end

  let(:helper) { helper_class.new }

  describe "#next_weekday_at" do
    context "when today is a weekday" do
      it "returns today at specified time if time hasn't passed" do
        # Freeze time to a Monday at 8:00 AM
        monday = Time.new(2024, 1, 15, 8, 0, 0) # Monday
        allow(Time).to receive(:now).and_return(monday)

        result = helper.next_weekday_at(9, 0)

        expect(result.hour).to eq(9)
        expect(result.min).to eq(0)
        expect(result.wday).to eq(1) # Monday
        expect(result.day).to eq(15)
      end

      it "returns next weekday if time has passed today" do
        # Freeze time to a Monday at 10:00 AM
        monday = Time.new(2024, 1, 15, 10, 0, 0) # Monday
        allow(Time).to receive(:now).and_return(monday)

        result = helper.next_weekday_at(9, 0)

        expect(result.hour).to eq(9)
        expect(result.min).to eq(0)
        expect(result.wday).to eq(2) # Tuesday
        expect(result.day).to eq(16)
      end
    end

    context "when today is Saturday" do
      it "returns Monday at specified time" do
        saturday = Time.new(2024, 1, 13, 10, 0, 0) # Saturday
        allow(Time).to receive(:now).and_return(saturday)

        result = helper.next_weekday_at(9, 0)

        expect(result.wday).to eq(1) # Monday
        expect(result.day).to eq(15)
        expect(result.hour).to eq(9)
      end
    end

    context "when today is Sunday" do
      it "returns Monday at specified time" do
        sunday = Time.new(2024, 1, 14, 10, 0, 0) # Sunday
        allow(Time).to receive(:now).and_return(sunday)

        result = helper.next_weekday_at(9, 0)

        expect(result.wday).to eq(1) # Monday
        expect(result.day).to eq(15)
        expect(result.hour).to eq(9)
      end
    end

    context "when it's Friday evening" do
      it "returns Monday at specified time" do
        friday_evening = Time.new(2024, 1, 12, 18, 0, 0) # Friday 6 PM
        allow(Time).to receive(:now).and_return(friday_evening)

        result = helper.next_weekday_at(9, 0)

        expect(result.wday).to eq(1) # Monday
        expect(result.day).to eq(15)
      end
    end
  end

  describe "#next_hour" do
    it "returns the start of the next hour" do
      current = Time.new(2024, 1, 15, 10, 30, 45)
      allow(Time).to receive(:now).and_return(current)

      result = helper.next_hour

      expect(result.hour).to eq(11)
      expect(result.min).to eq(0)
      expect(result.sec).to eq(0)
    end

    it "handles midnight transition" do
      current = Time.new(2024, 1, 15, 23, 30, 0)
      allow(Time).to receive(:now).and_return(current)

      result = helper.next_hour

      expect(result.hour).to eq(0) # Wraps to next day
    end
  end

  describe "#tomorrow_at" do
    it "returns tomorrow at the specified time" do
      current = Time.new(2024, 1, 15, 10, 0, 0)
      allow(Time).to receive(:now).and_return(current)

      result = helper.tomorrow_at(9, 30)

      expect(result.day).to eq(16)
      expect(result.hour).to eq(9)
      expect(result.min).to eq(30)
    end

    it "handles month transition" do
      current = Time.new(2024, 1, 31, 10, 0, 0)
      allow(Time).to receive(:now).and_return(current)

      result = helper.tomorrow_at(9, 0)

      expect(result.month).to eq(2)
      expect(result.day).to eq(1)
    end
  end

  describe "#in_business_hours" do
    context "during business hours on a weekday" do
      it "returns current time" do
        weekday_business_hours = Time.new(2024, 1, 15, 10, 30, 0) # Monday 10:30 AM
        allow(Time).to receive(:now).and_return(weekday_business_hours)

        result = helper.in_business_hours

        expect(result).to eq(weekday_business_hours)
      end
    end

    context "before business hours on a weekday" do
      it "returns start of business hours today" do
        weekday_early = Time.new(2024, 1, 15, 7, 0, 0) # Monday 7 AM
        allow(Time).to receive(:now).and_return(weekday_early)

        result = helper.in_business_hours

        expect(result.day).to eq(15)
        expect(result.hour).to eq(9)
        expect(result.min).to eq(0)
      end
    end

    context "after business hours on a weekday" do
      it "returns start of next business day" do
        weekday_late = Time.new(2024, 1, 15, 18, 0, 0) # Monday 6 PM
        allow(Time).to receive(:now).and_return(weekday_late)

        result = helper.in_business_hours

        expect(result.day).to eq(16) # Tuesday
        expect(result.hour).to eq(9)
      end
    end

    context "on a weekend" do
      it "returns start of Monday business hours" do
        saturday = Time.new(2024, 1, 13, 10, 0, 0) # Saturday
        allow(Time).to receive(:now).and_return(saturday)

        result = helper.in_business_hours

        expect(result.wday).to eq(1) # Monday
        expect(result.hour).to eq(9)
      end
    end

    context "with custom business hours" do
      it "respects custom start and end hours" do
        weekday = Time.new(2024, 1, 15, 7, 30, 0) # Monday 7:30 AM
        allow(Time).to receive(:now).and_return(weekday)

        result = helper.in_business_hours(start_hour: 8, end_hour: 16)

        expect(result.hour).to eq(8)
        expect(result.day).to eq(15)
      end

      it "considers current time within custom hours" do
        weekday = Time.new(2024, 1, 15, 8, 30, 0) # Monday 8:30 AM
        allow(Time).to receive(:now).and_return(weekday)

        result = helper.in_business_hours(start_hour: 8, end_hour: 16)

        expect(result).to eq(weekday)
      end
    end
  end

  describe "#next_day_at" do
    context "when target day is later this week" do
      it "returns that day at specified time" do
        monday = Time.new(2024, 1, 15, 10, 0, 0) # Monday
        allow(Time).to receive(:now).and_return(monday)

        result = helper.next_day_at(:wednesday, 14, 30)

        expect(result.wday).to eq(3) # Wednesday
        expect(result.day).to eq(17)
        expect(result.hour).to eq(14)
        expect(result.min).to eq(30)
      end
    end

    context "when target day is earlier in the week" do
      it "returns that day next week" do
        thursday = Time.new(2024, 1, 18, 10, 0, 0) # Thursday
        allow(Time).to receive(:now).and_return(thursday)

        result = helper.next_day_at(:monday, 9, 0)

        expect(result.wday).to eq(1) # Monday
        expect(result.day).to eq(22) # Next Monday
      end
    end

    context "when target day is today but time has passed" do
      it "returns same day next week" do
        monday_late = Time.new(2024, 1, 15, 15, 0, 0) # Monday 3 PM
        allow(Time).to receive(:now).and_return(monday_late)

        result = helper.next_day_at(:monday, 9, 0)

        expect(result.wday).to eq(1) # Monday
        expect(result.day).to eq(22) # Next Monday
      end
    end

    context "when target day is today and time hasn't passed" do
      it "returns today at specified time" do
        monday_early = Time.new(2024, 1, 15, 8, 0, 0) # Monday 8 AM
        allow(Time).to receive(:now).and_return(monday_early)

        result = helper.next_day_at(:monday, 9, 0)

        expect(result.wday).to eq(1) # Monday
        expect(result.day).to eq(15) # Today
        expect(result.hour).to eq(9)
      end
    end

    it "raises ArgumentError for unknown day" do
      expect {
        helper.next_day_at(:funday, 9, 0)
      }.to raise_error(ArgumentError, /Unknown day/)
    end

    it "accepts string day names" do
      monday = Time.new(2024, 1, 15, 10, 0, 0)
      allow(Time).to receive(:now).and_return(monday)

      result = helper.next_day_at("wednesday", 9, 0)

      expect(result.wday).to eq(3)
    end
  end

  describe "#next_month_at" do
    it "returns first of next month by default" do
      current = Time.new(2024, 1, 15, 10, 0, 0)
      allow(Time).to receive(:now).and_return(current)

      result = helper.next_month_at

      expect(result.month).to eq(2)
      expect(result.day).to eq(1)
      expect(result.hour).to eq(0)
      expect(result.min).to eq(0)
    end

    it "returns specified day of next month" do
      current = Time.new(2024, 1, 15, 10, 0, 0)
      allow(Time).to receive(:now).and_return(current)

      result = helper.next_month_at(day: 15, hour: 9, minute: 30)

      expect(result.month).to eq(2)
      expect(result.day).to eq(15)
      expect(result.hour).to eq(9)
      expect(result.min).to eq(30)
    end

    it "handles year transition" do
      december = Time.new(2024, 12, 15, 10, 0, 0)
      allow(Time).to receive(:now).and_return(december)

      result = helper.next_month_at

      expect(result.year).to eq(2025)
      expect(result.month).to eq(1)
      expect(result.day).to eq(1)
    end
  end

  describe "#from_now" do
    it "returns time offset from now in seconds" do
      current = Time.new(2024, 1, 15, 10, 0, 0)
      allow(Time).to receive(:now).and_return(current)

      result = helper.from_now(3600) # 1 hour

      expect(result).to eq(current + 3600)
    end

    it "accepts float seconds" do
      current = Time.new(2024, 1, 15, 10, 0, 0)
      allow(Time).to receive(:now).and_return(current)

      result = helper.from_now(1.5)

      expect(result).to eq(current + 1.5)
    end

    it "handles negative offsets" do
      current = Time.new(2024, 1, 15, 10, 0, 0)
      allow(Time).to receive(:now).and_return(current)

      result = helper.from_now(-3600)

      expect(result).to eq(current - 3600)
    end
  end

  describe "timezone handling" do
    context "without timezone specified" do
      it "uses system timezone" do
        result = helper.from_now(0)
        expect(result.utc_offset).to eq(Time.now.utc_offset)
      end
    end

    context "with ActiveSupport::TimeZone available", skip: !defined?(ActiveSupport::TimeZone) do
      it "uses specified timezone for next_weekday_at" do
        monday = Time.new(2024, 1, 15, 8, 0, 0)
        allow(Time).to receive(:now).and_return(monday)

        result = helper.next_weekday_at(9, 0, timezone: "America/New_York")

        expect(result.hour).to eq(9)
      end

      it "uses specified timezone for tomorrow_at" do
        result = helper.tomorrow_at(9, 0, timezone: "America/New_York")
        expect(result.hour).to eq(9)
      end
    end
  end

  describe "workflow integration" do
    let(:workflow_class) do
      Class.new(RubyLLM::Agents::Workflow) do
        include RubyLLM::Agents::Workflow::DSL::ScheduleHelpers
      end
    end

    it "can be included in workflow classes" do
      workflow = workflow_class.new
      expect(workflow).to respond_to(:next_weekday_at)
      expect(workflow).to respond_to(:in_business_hours)
      expect(workflow).to respond_to(:next_day_at)
      expect(workflow).to respond_to(:next_month_at)
      expect(workflow).to respond_to(:from_now)
    end
  end
end

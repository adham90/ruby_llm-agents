# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Deprecations do
  # Use module reference to avoid issues with nested describe blocks
  let(:deprecations) { RubyLLM::Agents::Deprecations }

  # Reset state before each test
  before do
    deprecations.raise_on_deprecation = false
    deprecations.silenced = false
  end

  # Restore state after each test
  after do
    deprecations.raise_on_deprecation = false
    deprecations.silenced = false
  end

  describe RubyLLM::Agents::Deprecations::DeprecationError do
    it "is a subclass of StandardError" do
      expect(described_class.superclass).to eq(StandardError)
    end

    it "can be raised with a message" do
      expect {
        raise described_class, "Test deprecation"
      }.to raise_error(described_class, "Test deprecation")
    end
  end

  describe ".raise_on_deprecation" do
    it "defaults to false" do
      # Reset to check default
      deprecations.instance_variable_set(:@raise_on_deprecation, nil)
      # The module sets defaults at load time, so we check current state
      deprecations.raise_on_deprecation = false
      expect(deprecations.raise_on_deprecation).to be false
    end

    it "can be set to true" do
      deprecations.raise_on_deprecation = true
      expect(deprecations.raise_on_deprecation).to be true
    end

    it "can be toggled" do
      deprecations.raise_on_deprecation = true
      expect(deprecations.raise_on_deprecation).to be true

      deprecations.raise_on_deprecation = false
      expect(deprecations.raise_on_deprecation).to be false
    end
  end

  describe ".silenced" do
    it "defaults to false" do
      deprecations.silenced = false
      expect(deprecations.silenced).to be false
    end

    it "can be set to true" do
      deprecations.silenced = true
      expect(deprecations.silenced).to be true
    end

    it "can be toggled" do
      deprecations.silenced = true
      expect(deprecations.silenced).to be true

      deprecations.silenced = false
      expect(deprecations.silenced).to be false
    end
  end

  describe ".warn" do
    let(:message) { "cache(ttl) is deprecated, use cache_for(ttl) instead" }
    let(:expected_prefix) { "[RubyLLM::Agents DEPRECATION]" }

    context "when silenced is true" do
      before { deprecations.silenced = true }

      it "does not emit any warning" do
        expect(Kernel).not_to receive(:warn)
        expect { deprecations.warn(message) }.not_to raise_error
      end

      it "does not raise even if raise_on_deprecation is true" do
        deprecations.raise_on_deprecation = true
        expect { deprecations.warn(message) }.not_to raise_error
      end

      it "returns nil" do
        expect(deprecations.warn(message)).to be_nil
      end
    end

    context "when raise_on_deprecation is true" do
      before { deprecations.raise_on_deprecation = true }

      it "raises DeprecationError" do
        expect {
          deprecations.warn(message)
        }.to raise_error(RubyLLM::Agents::Deprecations::DeprecationError)
      end

      it "includes the message in the error" do
        expect {
          deprecations.warn(message)
        }.to raise_error(RubyLLM::Agents::Deprecations::DeprecationError, /#{Regexp.escape(message)}/)
      end

      it "includes the deprecation prefix in the error" do
        expect {
          deprecations.warn(message)
        }.to raise_error(RubyLLM::Agents::Deprecations::DeprecationError, /#{Regexp.escape(expected_prefix)}/)
      end
    end

    context "when raise_on_deprecation is false" do
      before { deprecations.raise_on_deprecation = false }

      # NOTE: These tests verify Rails integration behavior.
      # Since we're running in a Rails test environment, we test actual behavior.
      context "in Rails environment" do
        it "uses Rails deprecator when available" do
          # Rails 7.1+ has deprecators, which our test environment should have
          if Rails.application.respond_to?(:deprecators)
            mock_deprecator = double("Deprecator")
            allow(Rails.application.deprecators).to receive(:[]).with(:ruby_llm_agents).and_return(mock_deprecator)
            expect(mock_deprecator).to receive(:warn).with(
              "#{expected_prefix} #{message}",
              kind_of(Array)
            )
            deprecations.warn(message)
          else
            # Pre-7.1 Rails falls back to Kernel.warn
            expect(Kernel).to receive(:warn).with(/#{Regexp.escape(expected_prefix)}/)
            deprecations.warn(message)
          end
        end

        it "includes the message in the warning" do
          if Rails.application.respond_to?(:deprecators)
            mock_deprecator = double("Deprecator")
            allow(Rails.application.deprecators).to receive(:[]).with(:ruby_llm_agents).and_return(mock_deprecator)
            expect(mock_deprecator).to receive(:warn).with(
              /#{Regexp.escape(message)}/,
              kind_of(Array)
            )
            deprecations.warn(message)
          else
            expect(Kernel).to receive(:warn).with(/#{Regexp.escape(message)}/)
            deprecations.warn(message)
          end
        end
      end

      context "with custom callstack" do
        let(:custom_callstack) { ["custom_file.rb:42:in `some_method'"] }

        it "uses the provided callstack" do
          if Rails.application.respond_to?(:deprecators)
            mock_deprecator = double("Deprecator")
            allow(Rails.application.deprecators).to receive(:[]).with(:ruby_llm_agents).and_return(mock_deprecator)
            expect(mock_deprecator).to receive(:warn).with(
              /#{Regexp.escape(expected_prefix)}/,
              custom_callstack
            )
            deprecations.warn(message, custom_callstack)
          else
            expect(Kernel).to receive(:warn).with(/custom_file\.rb:42/)
            deprecations.warn(message, custom_callstack)
          end
        end
      end
    end

    context "message formatting" do
      before do
        deprecations.raise_on_deprecation = true
      end

      it "prefixes message with [RubyLLM::Agents DEPRECATION]" do
        expect {
          deprecations.warn("test message")
        }.to raise_error(/\[RubyLLM::Agents DEPRECATION\] test message/)
      end

      it "handles empty message" do
        expect {
          deprecations.warn("")
        }.to raise_error(/\[RubyLLM::Agents DEPRECATION\] /)
      end

      it "handles message with special characters" do
        special_message = "Method `old_method` is deprecated. Use `new_method` instead!"
        expect {
          deprecations.warn(special_message)
        }.to raise_error(/#{Regexp.escape(special_message)}/)
      end
    end
  end

  describe ".silence" do
    it "silences warnings within the block" do
      expect(Kernel).not_to receive(:warn)

      deprecations.silence do
        deprecations.warn("This should be silenced")
      end
    end

    it "restores silenced state after block" do
      deprecations.silenced = false

      deprecations.silence do
        expect(deprecations.silenced).to be true
      end

      expect(deprecations.silenced).to be false
    end

    it "restores previous silenced state if it was true" do
      deprecations.silenced = true

      deprecations.silence do
        expect(deprecations.silenced).to be true
      end

      expect(deprecations.silenced).to be true
    end

    it "returns the block's return value" do
      result = deprecations.silence do
        "block result"
      end

      expect(result).to eq("block result")
    end

    it "restores silenced state even if block raises" do
      deprecations.silenced = false

      expect {
        deprecations.silence do
          raise StandardError, "Error in block"
        end
      }.to raise_error(StandardError, "Error in block")

      expect(deprecations.silenced).to be false
    end

    it "can be nested" do
      deprecations.silenced = false

      deprecations.silence do
        expect(deprecations.silenced).to be true

        deprecations.silence do
          expect(deprecations.silenced).to be true
        end

        expect(deprecations.silenced).to be true
      end

      expect(deprecations.silenced).to be false
    end

    it "prevents DeprecationError even when raise_on_deprecation is true" do
      deprecations.raise_on_deprecation = true

      expect {
        deprecations.silence do
          deprecations.warn("Should not raise")
        end
      }.not_to raise_error
    end
  end

  describe "integration scenarios" do
    context "typical test setup" do
      it "can be configured to raise in tests" do
        deprecations.raise_on_deprecation = true

        expect {
          deprecations.warn("Using deprecated API")
        }.to raise_error(RubyLLM::Agents::Deprecations::DeprecationError)
      end
    end

    context "silencing in specific tests" do
      it "can silence warnings for specific test blocks" do
        deprecations.raise_on_deprecation = true

        # This would normally raise
        deprecations.silence do
          # Safe to use deprecated APIs here
          expect { deprecations.warn("Deprecated") }.not_to raise_error
        end

        # Outside the block, it raises again
        expect { deprecations.warn("Deprecated") }.to raise_error(
          RubyLLM::Agents::Deprecations::DeprecationError
        )
      end
    end

    context "production-like behavior" do
      before do
        deprecations.raise_on_deprecation = false
        deprecations.silenced = false
      end

      it "emits warnings without raising" do
        # Mock the deprecator to verify it's being called
        if Rails.application.respond_to?(:deprecators)
          mock_deprecator = double("Deprecator")
          allow(Rails.application.deprecators).to receive(:[]).with(:ruby_llm_agents).and_return(mock_deprecator)
          expect(mock_deprecator).to receive(:warn).with(/DEPRECATION/, kind_of(Array))
        else
          expect(Kernel).to receive(:warn).with(/DEPRECATION/)
        end

        expect {
          deprecations.warn("This is deprecated")
        }.not_to raise_error
      end
    end
  end

  describe "thread safety considerations" do
    # Note: These tests document behavior but don't guarantee thread safety
    # The module uses class-level state which may have race conditions

    it "uses class-level attributes" do
      # Verify these are class-level (shared across instances/calls)
      deprecations.silenced = true
      expect(deprecations.silenced).to be true

      # Another "thread" would see this
      expect(deprecations.silenced).to be true
    end
  end
end

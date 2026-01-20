# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::ImageGenerator::ContentPolicy do
  describe ".validate!" do
    context "with :none policy" do
      it "allows any content" do
        expect { described_class.validate!("anything", :none) }.not_to raise_error
      end
    end

    context "with :standard policy" do
      it "allows safe content" do
        expect { described_class.validate!("A beautiful sunset", :standard) }.not_to raise_error
      end

      it "allows content that would be blocked by stricter policies" do
        expect { described_class.validate!("A dramatic weapon", :standard) }.not_to raise_error
      end
    end

    context "with :moderate policy" do
      it "allows safe content" do
        expect { described_class.validate!("A beautiful sunset", :moderate) }.not_to raise_error
      end

      it "blocks explicit content" do
        expect {
          described_class.validate!("nude figure", :moderate)
        }.to raise_error(RubyLLM::Agents::ImageGenerator::ContentPolicyViolation)
      end

      it "blocks gore content" do
        expect {
          described_class.validate!("graphic violence scene", :moderate)
        }.to raise_error(RubyLLM::Agents::ImageGenerator::ContentPolicyViolation)
      end
    end

    context "with :strict policy" do
      it "allows safe content" do
        expect { described_class.validate!("A beautiful sunset", :strict) }.not_to raise_error
      end

      it "blocks violent content" do
        expect {
          described_class.validate!("violent scene", :strict)
        }.to raise_error(RubyLLM::Agents::ImageGenerator::ContentPolicyViolation)
      end

      it "blocks weapon references" do
        expect {
          described_class.validate!("a gun on a table", :strict)
        }.to raise_error(RubyLLM::Agents::ImageGenerator::ContentPolicyViolation)
      end

      it "blocks explicit content" do
        expect {
          described_class.validate!("nsfw content", :strict)
        }.to raise_error(RubyLLM::Agents::ImageGenerator::ContentPolicyViolation)
      end

      it "blocks drug references" do
        expect {
          described_class.validate!("cocaine on table", :strict)
        }.to raise_error(RubyLLM::Agents::ImageGenerator::ContentPolicyViolation)
      end
    end
  end

  describe ".valid?" do
    it "returns true for valid content" do
      expect(described_class.valid?("A sunset", :strict)).to be true
    end

    it "returns false for invalid content" do
      expect(described_class.valid?("violent scene", :strict)).to be false
    end
  end

  describe ".matched_pattern" do
    it "returns the matched pattern" do
      pattern = described_class.matched_pattern("violent scene", :strict)
      expect(pattern).to be_a(Regexp)
      expect("violent").to match(pattern)
    end

    it "returns nil when no match" do
      pattern = described_class.matched_pattern("a sunset", :strict)
      expect(pattern).to be_nil
    end
  end
end

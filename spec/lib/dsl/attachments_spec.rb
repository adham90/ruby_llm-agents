# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::DSL::Attachments do
  let(:test_class) do
    Class.new do
      extend RubyLLM::Agents::DSL::Attachments

      def self.name
        "TestAgent"
      end
    end
  end

  describe "#store_attachments" do
    it "is disabled by default" do
      expect(test_class.store_attachments).to be_nil
      expect(test_class.store_attachments_enabled?).to be(false)
    end

    it "accepts the :active_storage backend" do
      test_class.store_attachments(:active_storage)

      expect(test_class.store_attachments).to eq(:active_storage)
      expect(test_class.store_attachments_enabled?).to be(true)
    end

    it "raises ArgumentError for unsupported backends" do
      expect {
        test_class.store_attachments(:redis)
      }.to raise_error(ArgumentError, /Unsupported store_attachments backend/)
    end

    it "inherits the setting from the superclass" do
      parent = Class.new do
        extend RubyLLM::Agents::DSL::Attachments
        store_attachments :active_storage
      end
      child = Class.new(parent)

      expect(child.store_attachments).to eq(:active_storage)
      expect(child.store_attachments_enabled?).to be(true)
    end
  end
end

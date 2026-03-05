# frozen_string_literal: true

require "rails_helper"
require "ostruct"

RSpec.describe RubyLLM::Agents::Providers::Inception::Models do
  let(:capabilities) { RubyLLM::Agents::Providers::Inception::Capabilities }
  let(:slug) { "inception" }

  describe ".parse_list_models_response" do
    let(:api_response) do
      OpenStruct.new(body: {
        "data" => [
          {
            "id" => "mercury-2",
            "object" => "model",
            "created" => 1740000000,
            "owned_by" => "inception-labs"
          },
          {
            "id" => "mercury",
            "object" => "model",
            "created" => 1719000000,
            "owned_by" => "inception-labs"
          },
          {
            "id" => "mercury-coder-small",
            "object" => "model",
            "created" => 1714000000,
            "owned_by" => "inception-labs"
          },
          {
            "id" => "mercury-edit",
            "object" => "model",
            "created" => 1714000000,
            "owned_by" => "inception-labs"
          }
        ]
      })
    end

    let(:models) do
      described_class.parse_list_models_response(api_response, slug, capabilities)
    end

    it "returns an array of Model::Info objects" do
      expect(models).to all(be_a(RubyLLM::Model::Info))
    end

    it "parses the correct number of models" do
      expect(models.length).to eq(4)
    end

    context "mercury-2 model" do
      let(:model) { models.find { |m| m.id == "mercury-2" } }

      it "has correct id" do
        expect(model.id).to eq("mercury-2")
      end

      it "has correct display name" do
        expect(model.name).to eq("Mercury 2")
      end

      it "has correct provider slug" do
        expect(model.provider).to eq("inception")
      end

      it "has correct family" do
        expect(model.family).to eq("mercury")
      end

      it "parses created_at timestamp" do
        expect(model.created_at).to eq(Time.at(1740000000))
      end

      it "has correct context window" do
        expect(model.context_window).to eq(128_000)
      end

      it "has correct max output tokens" do
        expect(model.max_output_tokens).to eq(32_000)
      end

      it "has text-only modalities" do
        expect(model.modalities.input).to eq(["text"])
        expect(model.modalities.output).to eq(["text"])
      end

      it "has streaming, function_calling, structured_output, and reasoning capabilities" do
        expect(model.capabilities).to include("streaming", "function_calling", "structured_output", "reasoning")
      end

      it "has correct pricing" do
        expect(model.pricing.text_tokens.standard.input_per_million).to eq(0.25)
        expect(model.pricing.text_tokens.standard.output_per_million).to eq(0.75)
      end

      it "has metadata with object and owned_by" do
        expect(model.metadata).to eq({object: "model", owned_by: "inception-labs"})
      end
    end

    context "mercury-coder-small model" do
      let(:model) { models.find { |m| m.id == "mercury-coder-small" } }

      it "has correct display name" do
        expect(model.name).to eq("Mercury Coder Small")
      end

      it "has only streaming capability" do
        expect(model.capabilities).to eq(["streaming"])
      end

      it "has correct output pricing" do
        expect(model.pricing.text_tokens.standard.output_per_million).to eq(1.00)
      end
    end

    context "with empty response" do
      let(:empty_response) { OpenStruct.new(body: {"data" => []}) }

      it "returns empty array" do
        result = described_class.parse_list_models_response(empty_response, slug, capabilities)
        expect(result).to eq([])
      end
    end

    context "with nil data" do
      let(:nil_response) { OpenStruct.new(body: {"data" => nil}) }

      it "returns empty array" do
        result = described_class.parse_list_models_response(nil_response, slug, capabilities)
        expect(result).to eq([])
      end
    end

    context "with missing created timestamp" do
      let(:response_without_created) do
        OpenStruct.new(body: {
          "data" => [
            {"id" => "mercury-2", "object" => "model"}
          ]
        })
      end

      it "sets created_at to nil" do
        result = described_class.parse_list_models_response(response_without_created, slug, capabilities)
        expect(result.first.created_at).to be_nil
      end
    end

    context "with missing metadata fields" do
      let(:response_minimal) do
        OpenStruct.new(body: {
          "data" => [
            {"id" => "mercury-2"}
          ]
        })
      end

      it "compacts nil metadata values" do
        result = described_class.parse_list_models_response(response_minimal, slug, capabilities)
        expect(result.first.metadata).to eq({})
      end
    end
  end
end

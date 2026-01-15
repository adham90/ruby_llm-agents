# frozen_string_literal: true

require "rails_helper"

RSpec.describe "DSL Inheritance" do
  # Silence deprecation warnings for tests
  before do
    RubyLLM::Agents::Deprecations.silenced = true
  end

  after do
    RubyLLM::Agents::Deprecations.silenced = false
  end

  describe "parameter inheritance" do
    it "inherits params from parent class" do
      parent = Class.new(RubyLLM::Agents::Base) do
        param :query, required: true
      end

      child = Class.new(parent) do
        param :limit, default: 10
      end

      expect(child.params.keys).to contain_exactly(:query, :limit)
      expect(child.params[:query][:required]).to be true
    end

    it "allows child to override parent param defaults" do
      parent = Class.new(RubyLLM::Agents::Base) do
        param :limit, default: 10
      end

      child = Class.new(parent) do
        param :limit, default: 20
      end

      expect(child.params[:limit][:default]).to eq(20)
      expect(parent.params[:limit][:default]).to eq(10)
    end

    it "child inherits parent type constraint" do
      parent = Class.new(RubyLLM::Agents::Base) do
        param :count, type: Integer
      end

      child = Class.new(parent)

      expect(child.params[:count][:type]).to eq(Integer)
    end
  end

  describe "model inheritance" do
    it "inherits model from parent" do
      parent = Class.new(RubyLLM::Agents::Base) do
        model "gpt-4o"
      end

      child = Class.new(parent)

      expect(child.model).to eq("gpt-4o")
    end

    it "child can override parent model" do
      parent = Class.new(RubyLLM::Agents::Base) do
        model "gpt-4o"
      end

      child = Class.new(parent) do
        model "gpt-4o-mini"
      end

      expect(child.model).to eq("gpt-4o-mini")
      expect(parent.model).to eq("gpt-4o")
    end
  end

  describe "temperature inheritance" do
    it "inherits temperature from parent" do
      parent = Class.new(RubyLLM::Agents::Base) do
        temperature 0.7
      end

      child = Class.new(parent)

      expect(child.temperature).to eq(0.7)
    end
  end

  describe "reliability inheritance" do
    it "inherits retries config from parent" do
      parent = Class.new(RubyLLM::Agents::Base) do
        retries max: 3, backoff: :exponential
      end

      child = Class.new(parent)

      expect(child.retries[:max]).to eq(3)
      expect(child.retries[:backoff]).to eq(:exponential)
    end

    it "inherits fallback_models from parent" do
      parent = Class.new(RubyLLM::Agents::Base) do
        fallback_models ["gpt-4o-mini"]
      end

      child = Class.new(parent)

      expect(child.fallback_models).to include("gpt-4o-mini")
    end

    it "inherits reliability block settings" do
      parent = Class.new(RubyLLM::Agents::Base) do
        reliability do
          retries max: 2
          fallback_models "gpt-4o-mini"
          total_timeout 30
        end
      end

      child = Class.new(parent)

      expect(child.retries[:max]).to eq(2)
      expect(child.fallback_models).to include("gpt-4o-mini")
      expect(child.total_timeout).to eq(30)
    end
  end

  describe "tools inheritance" do
    let(:tool1) { Class.new { def self.name; "Tool1"; end } }
    let(:tool2) { Class.new { def self.name; "Tool2"; end } }

    it "inherits tools from parent" do
      t1 = tool1
      parent = Class.new(RubyLLM::Agents::Base) do
        tools [t1]
      end

      child = Class.new(parent)

      expect(child.tools).to include(t1)
    end

    it "child can replace parent tools" do
      t1 = tool1
      t2 = tool2

      parent = Class.new(RubyLLM::Agents::Base) do
        tools [t1]
      end

      child = Class.new(parent) do
        tools [t2]
      end

      expect(child.tools).to include(t2)
      expect(child.tools).not_to include(t1)
    end
  end

  describe "caching inheritance" do
    it "caching is not inherited by default" do
      parent = Class.new(RubyLLM::Agents::Base) do
        cache_for 1.hour
      end

      child = Class.new(parent)

      # cache_enabled? is class-specific, not inherited
      expect(parent.cache_enabled?).to be true
      expect(child.cache_enabled?).to be false
    end

    it "child can enable its own caching" do
      parent = Class.new(RubyLLM::Agents::Base)

      child = Class.new(parent) do
        cache_for 30.minutes
      end

      expect(parent.cache_enabled?).to be false
      expect(child.cache_enabled?).to be true
      expect(child.cache_ttl).to eq(30.minutes)
    end
  end

  describe "streaming inheritance" do
    it "inherits streaming setting from parent" do
      parent = Class.new(RubyLLM::Agents::Base) do
        streaming true
      end

      child = Class.new(parent)

      expect(child.streaming).to be true
    end

    it "child can override streaming" do
      parent = Class.new(RubyLLM::Agents::Base) do
        streaming true
      end

      child = Class.new(parent) do
        streaming false
      end

      expect(child.streaming).to be false
      expect(parent.streaming).to be true
    end
  end

  describe "description inheritance" do
    it "inherits description from parent" do
      parent = Class.new(RubyLLM::Agents::Base) do
        description "Parent description"
      end

      child = Class.new(parent)

      expect(child.description).to eq("Parent description")
    end

    it "child can override description" do
      parent = Class.new(RubyLLM::Agents::Base) do
        description "Parent description"
      end

      child = Class.new(parent) do
        description "Child description"
      end

      expect(child.description).to eq("Child description")
      expect(parent.description).to eq("Parent description")
    end
  end
end

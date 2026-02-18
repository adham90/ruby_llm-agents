# Multi-Source Universal Pricing Plan

## Problem

The gem currently has **three separate pricing modules** — `TranscriptionPricing`, `SpeechPricing`, and `ImageGenerator::Pricing` — each with its own copy-pasted LiteLLM fetch/cache code, and each querying only **one source**. If LiteLLM is down, stale, or missing a model, pricing fails silently or falls back to hardcoded values.

We want a **universal pricing layer** that:
1. Cascades across **multiple free public APIs** to maximize model coverage
2. Serves **all model types** (text LLM, transcription, TTS, image, embedding)
3. Caches aggressively to avoid hammering APIs
4. Eliminates the duplicated HTTP/cache code across 3 modules

---

## API Source Inventory

### Source 1: LiteLLM (Bulk JSON) — **Most comprehensive**
- **URL**: `GET https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json`
- **Coverage**: ~2,000+ models across all categories

| Category | Models | Key pricing fields |
|----------|--------|--------------------|
| Text LLM | 1,000+ | `input_cost_per_token`, `output_cost_per_token` |
| Transcription | 57 | `input_cost_per_second` (45), `input_cost_per_audio_token` (8) |
| TTS/Speech | some | `input_cost_per_character`, `output_cost_per_character` |
| Image | some | `input_cost_per_image`, `input_cost_per_pixel` |
| Embedding | some | `input_cost_per_token` (with `mode: "embedding"`) |

- **Pros**: Single bulk fetch; well-documented units; community-updated; covers all model types
- **Cons**: ~2MB payload; raw GitHub file (not a real API); can lag behind price changes

### Source 2: Portkey AI (Per-Model Query) — **Targeted fallback, broadest catalog**
- **URL**: `GET https://api.portkey.ai/model-configs/pricing/{provider}/{model}`
- **Coverage**: 3,000+ models across 40+ providers

| Category | Coverage | Key pricing fields |
|----------|----------|--------------------|
| Text LLM | Excellent | `pay_as_you_go.request_token.price`, `response_token.price` |
| Transcription | Key models | `additional_units.request_audio_token.price` |
| TTS/Speech | Likely | Same structure, audio output tokens |
| Image | Likely | Per-image or per-pixel fields |
| Embedding | Likely | `request_token.price` |

- **Unit**: Prices are in **cents per token** (verified: `0.00025` for gpt-4o-transcribe request_token = $2.50/1M)
- **Pros**: Per-model queries (tiny response); very fresh; no auth required; widest provider coverage
- **Cons**: One HTTP call per model lookup; requires knowing `{provider}/{model}` format

### Source 3: OpenRouter (Bulk Models List) — **Good for text LLM + audio chat models**
- **URL**: `GET https://openrouter.ai/api/v1/models`
- **Coverage**: 400+ models

| Category | Coverage | Key pricing fields |
|----------|----------|--------------------|
| Text LLM | 400+ | `pricing.prompt`, `pricing.completion` (strings, USD per token) |
| Audio chat | ~5 models | `pricing.audio` (per-token or per-second, varies) |
| Transcription | None | No whisper-1, no gpt-4o-transcribe |
| Image | None | No image generation models |
| Embedding | None | No embedding models listed |

- **Pros**: Single bulk fetch; real-time pricing updates; public; rich metadata (context length, modalities)
- **Cons**: Prices are **strings** not numbers; no dedicated transcription/image/embedding models; `pricing.audio` unit ambiguity

### Source 4: Helicone — **Text LLM only, decent size**
- **URL**: `GET https://www.helicone.ai/api/llm-costs`
- **Coverage**: 172 models (text LLM focus)

| Category | Coverage | Key pricing fields |
|----------|----------|--------------------|
| Text LLM | 172 | `input_cost_per_1m`, `output_cost_per_1m` |
| Audio (realtime) | ~10 | `prompt_audio_per_1m`, `completion_audio_per_1m` |
| Transcription | None | No whisper/transcription entries |
| TTS/Image/Embed | None | Not covered |

- **Pros**: Clean schema; per-1M-token pricing (easy to normalize); `?provider=` filter support
- **Cons**: Only text LLM + realtime audio; no transcription/TTS/image/embedding

### Source 5: LLM Pricing AI — **Smallest, text LLM only**
- **URL**: `GET https://llmpricing.ai/api/models` (list) + `GET https://llmpricing.ai/api/prices?provider=X&model=Y&input_tokens=N&output_tokens=N` (calculate)
- **Coverage**: ~79 models across 4 providers (OpenAI, Anthropic, Groq, Mistral)

| Category | Coverage | Key pricing fields |
|----------|----------|--------------------|
| Text LLM | 79 | `input_cost`, `output_cost` (calculated, not raw rates) |
| Everything else | None | Not covered |

- **Pros**: Simple API; community-maintained
- **Cons**: Very limited (4 providers); only returns calculated costs, not raw per-token rates; no audio/image/embedding

---

## Coverage Matrix

Which source covers which model type:

| Source | Text LLM | Transcription | TTS | Image | Embedding | Fetch style |
|--------|:-:|:-:|:-:|:-:|:-:|-------------|
| LiteLLM | ++ | ++ | + | + | + | Bulk (1 call) |
| Portkey | ++ | + | + | + | + | Per-model |
| OpenRouter | ++ | - | - | - | - | Bulk (1 call) |
| Helicone | + | - | - | - | - | Bulk (1 call) |
| LLM Pricing AI | ~ | - | - | - | - | Per-model |

`++` = excellent, `+` = some coverage, `-` = none, `~` = minimal

---

## Recommended Source Priority

### For text LLM / embedding models
```
1. User config              (instant)
2. RubyLLM gem              (local, no HTTP, already a dependency)
3. LiteLLM                  (bulk, most complete)
4. Portkey AI               (per-model fallback)
5. OpenRouter               (bulk, 400+ text models)
6. Helicone                 (bulk, 172 text models)
7. LLM Pricing AI           (per-model, 79 models, last resort)
```

### For transcription models
```
1. User config
2. RubyLLM gem              (local, if model is in registry)
3. LiteLLM                  (57 transcription models)
4. Portkey AI               (key transcription models confirmed)
5. OpenRouter               (audio-capable chat models only)
6. Helicone                 (no transcription — pass-through, future-proof)
6. LLM Pricing AI           (no transcription — pass-through, future-proof)
```

### For TTS / speech models
```
1. User config
2. LiteLLM                  (has TTS pricing fields)
3. Portkey AI               (per-model fallback)
4. ElevenLabs API           (existing Tier 3 — keep as-is)
5. OpenRouter / Helicone    (limited, future-proof)
```

### For image generation models
```
1. User config
2. LiteLLM                  (has per-image pricing)
3. Portkey AI               (per-model fallback)
4. OpenRouter / Helicone    (no image models — future-proof)
```

---

## Architecture

### `lib/ruby_llm/agents/pricing/` — New shared pricing namespace

```
lib/ruby_llm/agents/pricing/
├── data_store.rb             # Shared HTTP fetch + two-layer cache
├── litellm_adapter.rb        # LiteLLM bulk JSON → normalized pricing
├── portkey_adapter.rb        # Portkey per-model → normalized pricing
├── openrouter_adapter.rb     # OpenRouter bulk JSON → normalized pricing
├── helicone_adapter.rb       # Helicone bulk JSON → normalized pricing
└── llmpricing_adapter.rb     # LLM Pricing AI per-model → normalized pricing
```

### `Pricing::DataStore` — Centralized HTTP + caching

Replaces the duplicated `fetch_from_url` / `litellm_data` / `cache_expired?` code currently copy-pasted across `TranscriptionPricing`, `SpeechPricing`, and `ImageGenerator::Pricing`.

```ruby
module RubyLLM::Agents::Pricing
  module DataStore
    extend self

    # Bulk fetchers (one HTTP call gets all models)
    def litellm_data       # → Hash (model_id => {...})
    def openrouter_data    # → Array of model entries
    def helicone_data      # → Array of cost entries

    # Per-model fetchers (one HTTP call per model)
    def portkey_data(provider, model)   # → Hash (pricing for one model)
    def llmpricing_data(provider, model, input_tokens, output_tokens)  # → Hash

    # Cache management
    def refresh!(source = :all)
    def cache_stats  # → { litellm: { fetched_at:, size: }, ... }
  end
end
```

### Two-layer cache

```
Layer 1: In-memory (per-process, instant)
├── @litellm_data          + @litellm_fetched_at
├── @openrouter_data       + @openrouter_fetched_at
├── @helicone_data         + @helicone_fetched_at
└── @portkey_cache[key]    + @portkey_fetched_at[key]
    @llmpricing_cache[key] + @llmpricing_fetched_at[key]

Layer 2: Rails.cache (cross-process, survives restarts)
├── "ruby_llm_agents:pricing:litellm"              expires_in: TTL
├── "ruby_llm_agents:pricing:openrouter"            expires_in: TTL
├── "ruby_llm_agents:pricing:helicone"              expires_in: TTL
├── "ruby_llm_agents:pricing:portkey:{provider}/{model}"  expires_in: TTL
└── "ruby_llm_agents:pricing:llmpricing:{provider}/{model}" expires_in: TTL
```

### Normalized pricing format

Each adapter converts its source-specific response into a common structure:

```ruby
# What each adapter returns for a given model:
{
  input_cost_per_token: Float,        # USD per token (text LLM, embedding)
  output_cost_per_token: Float,       # USD per token (text LLM)
  input_cost_per_second: Float,       # USD per second (transcription)
  input_cost_per_audio_token: Float,  # USD per audio token (gpt-4o-transcribe)
  input_cost_per_character: Float,    # USD per character (TTS)
  input_cost_per_image: Float,        # USD per image (image generation)
  mode: String,                       # "chat", "audio_transcription", "tts", "embedding", "image_generation"
  source: Symbol,                     # :litellm, :portkey, :openrouter, :helicone, :llmpricing
}
```

This lets each domain-specific pricing module (TranscriptionPricing, SpeechPricing, etc.) extract what it needs.

### Adapter details

#### LiteLLM Adapter

```ruby
module Pricing::LiteLLMAdapter
  extend self

  def find_model(model_id)
    data = DataStore.litellm_data
    return nil unless data&.any?

    # Candidate key matching (exact, normalized, prefixed, fuzzy)
    model_data = find_by_candidates(data, model_id)
    return nil unless model_data

    normalize(model_data)
  end

  private

  def normalize(raw)
    {
      input_cost_per_token:       raw["input_cost_per_token"],
      output_cost_per_token:      raw["output_cost_per_token"],
      input_cost_per_second:      raw["input_cost_per_second"],
      input_cost_per_audio_token: raw["input_cost_per_audio_token"],
      input_cost_per_character:   raw["input_cost_per_character"],
      output_cost_per_character:  raw["output_cost_per_character"],
      input_cost_per_image:       raw["input_cost_per_image"],
      mode:                       raw["mode"],
      source:                     :litellm
    }.compact
  end
end
```

#### Portkey Adapter

```ruby
module Pricing::PortkeyAdapter
  extend self

  PROVIDER_MAP = {
    /^(gpt-|whisper|dall-e|tts-)/ => "openai",
    /^claude/ => "anthropic",
    /^gemini/ => "google",
    /^mistral/ => "mistralai",
    /^llama/ => "meta",
    /^azure\// => ->(id) { ["azure", id.sub("azure/", "")] },
    /^groq\// => ->(id) { ["groq", id.sub("groq/", "")] },
    /^deepgram\// => ->(id) { ["deepgram", id.sub("deepgram/", "")] },
  }.freeze

  def find_model(model_id)
    provider, model_name = resolve_provider(model_id)
    return nil unless provider

    raw = DataStore.portkey_data(provider, model_name)
    return nil unless raw && raw["pay_as_you_go"]

    normalize(raw)
  end

  private

  def normalize(raw)
    pag = raw["pay_as_you_go"]
    additional = pag["additional_units"] || {}

    # Portkey prices are in cents per token
    req_token  = pag.dig("request_token", "price")
    resp_token = pag.dig("response_token", "price")
    audio_in   = additional.dig("request_audio_token", "price")
    audio_out  = additional.dig("response_audio_token", "price")

    result = { source: :portkey }

    # Convert cents/token → USD/token
    result[:input_cost_per_token]       = req_token / 100.0 if req_token&.positive?
    result[:output_cost_per_token]      = resp_token / 100.0 if resp_token&.positive?
    result[:input_cost_per_audio_token] = audio_in / 100.0 if audio_in&.positive?

    result.compact
  end
end
```

#### OpenRouter Adapter

```ruby
module Pricing::OpenRouterAdapter
  extend self

  def find_model(model_id)
    models = DataStore.openrouter_data
    return nil unless models&.any?

    entry = find_by_id(models, model_id)
    return nil unless entry

    normalize(entry)
  end

  private

  def normalize(entry)
    pricing = entry["pricing"] || {}

    result = { source: :openrouter }

    # OpenRouter prices are strings (USD per token)
    result[:input_cost_per_token]  = pricing["prompt"].to_f if pricing["prompt"]
    result[:output_cost_per_token] = pricing["completion"].to_f if pricing["completion"]

    if pricing["audio"]
      # Unit depends on model — store raw, let consumer decide
      result[:audio_cost_raw] = pricing["audio"].to_f
      result[:audio_modality] = entry.dig("architecture", "modality")
    end

    if pricing["image"]
      result[:image_cost_raw] = pricing["image"].to_f
    end

    result.compact
  end
end
```

#### Helicone Adapter

```ruby
module Pricing::HeliconeAdapter
  extend self

  def find_model(model_id)
    data = DataStore.helicone_data
    return nil unless data&.any?

    entry = find_matching(data, model_id)
    return nil unless entry

    normalize(entry)
  end

  private

  def normalize(entry)
    result = { source: :helicone }

    # Helicone prices are per 1M tokens
    if entry["input_cost_per_1m"]
      result[:input_cost_per_token] = entry["input_cost_per_1m"] / 1_000_000.0
    end
    if entry["output_cost_per_1m"]
      result[:output_cost_per_token] = entry["output_cost_per_1m"] / 1_000_000.0
    end
    if entry["prompt_audio_per_1m"]
      result[:input_cost_per_audio_token] = entry["prompt_audio_per_1m"] / 1_000_000.0
    end

    result.compact
  end
end
```

#### LLM Pricing AI Adapter

```ruby
module Pricing::LLMPricingAdapter
  extend self

  PROVIDER_MAP = {
    /^(gpt-|whisper|dall-e|tts-|o1|o3)/ => "OpenAI",
    /^claude/ => "Anthropic",
    /^(mixtral|mistral|codestral)/ => "Mistral",
    /^(gemma|llama)/ => "Groq",
  }.freeze

  def find_model(model_id)
    provider = resolve_provider(model_id)
    return nil unless provider

    # This API returns calculated costs, not raw rates
    # Query with 1M tokens to get per-1M pricing
    raw = DataStore.llmpricing_data(provider, model_id, 1_000_000, 1_000_000)
    return nil unless raw && raw["input_cost"]

    normalize(raw)
  end

  private

  def normalize(raw)
    # Prices returned are for 1M tokens
    {
      input_cost_per_token:  raw["input_cost"] / 1_000_000.0,
      output_cost_per_token: raw["output_cost"] / 1_000_000.0,
      source: :llmpricing
    }.compact
  end
end
```

---

### Consumer modules (refactored)

Each existing pricing module becomes a thin consumer of the shared adapters:

#### TranscriptionPricing (refactored)

```ruby
module TranscriptionPricing
  extend self

  SOURCES = [:config, :litellm, :portkey, :openrouter, :helicone, :llmpricing].freeze

  def cost_per_minute(model_id)
    SOURCES.each do |source|
      price = send(:"from_#{source}", model_id)
      return price if price
    end
    nil
  end

  private

  def from_config(model_id)
    # existing user config lookup
  end

  def from_litellm(model_id)
    data = Pricing::LiteLLMAdapter.find_model(model_id)
    return nil unless data
    extract_per_minute(data)
  end

  def from_portkey(model_id)
    data = Pricing::PortkeyAdapter.find_model(model_id)
    return nil unless data
    extract_per_minute(data)
  end

  # ... same pattern for openrouter, helicone, llmpricing

  def extract_per_minute(data)
    if data[:input_cost_per_second]
      return data[:input_cost_per_second] * 60
    end
    if data[:input_cost_per_audio_token]
      # ~25 audio tokens/second = 1500/minute
      return data[:input_cost_per_audio_token] * 1500
    end
    nil
  end
end
```

#### SpeechPricing (refactored)

```ruby
module SpeechPricing
  def cost_per_1k_characters(provider, model_id)
    # 1. Config override
    # 2. LiteLLM → extract input_cost_per_character * 1000
    # 3. Portkey → extract from response
    # 4. ElevenLabs API (existing, kept as-is)
    # 5. OpenRouter / Helicone (future-proof)
    # 6. Existing hardcoded fallbacks (kept until all sources cover TTS)
  end
end
```

#### ImageGenerator::Pricing (refactored)

```ruby
module ImageGenerator::Pricing
  def cost_per_image(model_id, size:, quality:)
    # 1. Config override
    # 2. LiteLLM → extract input_cost_per_image
    # 3. Portkey → extract from response
    # 4. OpenRouter / Helicone (future-proof)
    # 5. Existing hardcoded fallbacks (kept until all sources cover images)
  end
end
```

---

## Caching Strategy

### TTL Configuration

```ruby
# In configuration.rb — single unified TTL
attr_accessor :pricing_cache_ttl  # default: 86400 (24 hours)
```

Existing `litellm_pricing_cache_ttl` continues to work for backward compat (takes precedence over `pricing_cache_ttl` for LiteLLM specifically if set).

### Cache keys

| Source | Rails.cache key | Default TTL |
|--------|----------------|-------------|
| LiteLLM | `"ruby_llm_agents:pricing:litellm"` | 24h |
| OpenRouter | `"ruby_llm_agents:pricing:openrouter"` | 24h |
| Helicone | `"ruby_llm_agents:pricing:helicone"` | 24h |
| Portkey | `"ruby_llm_agents:pricing:portkey:{provider}/{model}"` | 24h |
| LLM Pricing AI | `"ruby_llm_agents:pricing:llmpricing:{provider}/{model}"` | 24h |

### Lazy fetching

Sources are fetched **lazily in cascade order**. If LiteLLM has the price, Portkey/OpenRouter/Helicone are never called. This minimizes HTTP calls on the hot path.

### Refresh API

```ruby
Pricing::DataStore.refresh!              # all sources
Pricing::DataStore.refresh!(:litellm)    # just LiteLLM
Pricing::DataStore.refresh!(:portkey)    # all Portkey entries
Pricing::DataStore.refresh!(:openrouter) # just OpenRouter
Pricing::DataStore.refresh!(:helicone)   # just Helicone
Pricing::DataStore.refresh!(:llmpricing) # all LLM Pricing AI entries
```

---

## Configuration Changes

### New attributes in `configuration.rb`

```ruby
# Unified pricing cache TTL (all sources)
attr_accessor :pricing_cache_ttl           # default: 86400 (24h)

# Per-source enable/disable
attr_accessor :portkey_pricing_enabled     # default: true
attr_accessor :openrouter_pricing_enabled  # default: true
attr_accessor :helicone_pricing_enabled    # default: true
attr_accessor :llmpricing_enabled          # default: true

# Per-source URL overrides
attr_accessor :portkey_pricing_url         # default: "https://api.portkey.ai/model-configs/pricing"
attr_accessor :openrouter_pricing_url      # default: "https://openrouter.ai/api/v1/models"
attr_accessor :helicone_pricing_url        # default: "https://www.helicone.ai/api/llm-costs"
attr_accessor :llmpricing_url              # default: "https://llmpricing.ai/api"
```

Existing `litellm_pricing_url` and `litellm_pricing_cache_ttl` remain for backward compat.

---

## Files to Create/Modify

| File | Action | Description |
|------|--------|-------------|
| `lib/ruby_llm/agents/pricing/data_store.rb` | **Create** | Shared HTTP fetch + two-layer cache for all sources |
| `lib/ruby_llm/agents/pricing/litellm_adapter.rb` | **Create** | LiteLLM JSON → normalized pricing (extracted from 3 modules) |
| `lib/ruby_llm/agents/pricing/portkey_adapter.rb` | **Create** | Portkey per-model API → normalized pricing |
| `lib/ruby_llm/agents/pricing/openrouter_adapter.rb` | **Create** | OpenRouter bulk API → normalized pricing |
| `lib/ruby_llm/agents/pricing/helicone_adapter.rb` | **Create** | Helicone bulk API → normalized pricing |
| `lib/ruby_llm/agents/pricing/llmpricing_adapter.rb` | **Create** | LLM Pricing AI per-model → normalized pricing |
| `lib/ruby_llm/agents/audio/transcription_pricing.rb` | **Modify** | Multi-source cascade using adapters |
| `lib/ruby_llm/agents/audio/speech_pricing.rb` | **Modify** | Multi-source cascade using adapters |
| `lib/ruby_llm/agents/image/generator/pricing.rb` | **Modify** | Multi-source cascade using adapters |
| `lib/ruby_llm/agents/core/configuration.rb` | **Modify** | Add new config attrs + defaults |
| `spec/lib/pricing/data_store_integration_spec.rb` | **Create** | Integration tests for DataStore |
| `spec/lib/pricing/litellm_adapter_integration_spec.rb` | **Create** | Integration tests |
| `spec/lib/pricing/portkey_adapter_integration_spec.rb` | **Create** | Integration tests |
| `spec/lib/pricing/openrouter_adapter_integration_spec.rb` | **Create** | Integration tests |
| `spec/lib/pricing/helicone_adapter_integration_spec.rb` | **Create** | Integration tests |
| `spec/lib/pricing/llmpricing_adapter_integration_spec.rb` | **Create** | Integration tests |
| `spec/lib/audio/transcription_pricing_integration_spec.rb` | **Create** | End-to-end multi-source tests |
| `spec/lib/audio/speech_pricing_integration_spec.rb` | **Create** | End-to-end multi-source tests |

---

## Testing Strategy (No Mocks for Integration)

### Integration tests — tag `:integration`, hit real APIs

```ruby
# spec/rails_helper.rb
RSpec.configure do |config|
  config.filter_run_excluding integration: true unless ENV["RUN_INTEGRATION"]
end
```

```bash
# Run integration tests
RUN_INTEGRATION=1 bundle exec rspec --tag integration

# Run everything
RUN_INTEGRATION=1 bundle exec rspec
```

### DataStore integration spec

```ruby
RSpec.describe RubyLLM::Agents::Pricing::DataStore, :integration do
  describe ".litellm_data" do
    it "fetches and returns a large hash" do
      data = described_class.litellm_data
      expect(data).to be_a(Hash)
      expect(data.size).to be > 500
    end

    it "contains whisper-1 with input_cost_per_second" do
      data = described_class.litellm_data
      expect(data["whisper-1"]).to be_a(Hash)
      expect(data["whisper-1"]["input_cost_per_second"]).to be > 0
    end

    it "contains gpt-4o with input_cost_per_token" do
      data = described_class.litellm_data
      expect(data["gpt-4o"]).to be_a(Hash)
      expect(data["gpt-4o"]["input_cost_per_token"]).to be > 0
    end
  end

  describe ".openrouter_data" do
    it "fetches and returns an array of models" do
      data = described_class.openrouter_data
      expect(data).to be_an(Array)
      expect(data.size).to be > 100
    end

    it "models have pricing with prompt and completion" do
      data = described_class.openrouter_data
      model = data.find { |m| m["id"]&.include?("gpt-4o") }
      expect(model).to be_present
      expect(model.dig("pricing", "prompt")).to be_present
    end
  end

  describe ".helicone_data" do
    it "fetches and returns model cost entries" do
      data = described_class.helicone_data
      expect(data).to be_an(Array)
      expect(data.size).to be > 50
    end

    it "entries have input_cost_per_1m" do
      data = described_class.helicone_data
      openai_entry = data.find { |e| e["provider"] == "OPENAI" && e["model"]&.include?("gpt-4o") }
      expect(openai_entry).to be_present
      expect(openai_entry["input_cost_per_1m"]).to be > 0
    end
  end

  describe ".portkey_data" do
    it "returns pricing for openai/gpt-4o" do
      data = described_class.portkey_data("openai", "gpt-4o")
      expect(data).to be_a(Hash)
      expect(data.dig("pay_as_you_go", "request_token", "price")).to be > 0
    end

    it "returns pricing for openai/whisper-1" do
      data = described_class.portkey_data("openai", "whisper-1")
      expect(data).to be_a(Hash)
      expect(data.dig("pay_as_you_go", "additional_units", "request_audio_token", "price")).to be > 0
    end

    it "returns nil-like for nonexistent models" do
      data = described_class.portkey_data("openai", "fake-model-xyz-999")
      expect(data).to satisfy { |d| d.nil? || d.empty? || !d.key?("pay_as_you_go") }
    end
  end

  describe ".llmpricing_data" do
    it "returns pricing for OpenAI/gpt-4o" do
      data = described_class.llmpricing_data("OpenAI", "gpt-4o", 1_000_000, 1_000_000)
      expect(data).to be_a(Hash)
      expect(data["input_cost"]).to be > 0
      expect(data["output_cost"]).to be > 0
    end
  end

  describe "caching" do
    it "second fetch is instant (in-memory cache)" do
      described_class.refresh!(:litellm)

      t1 = Benchmark.realtime { described_class.litellm_data }
      t2 = Benchmark.realtime { described_class.litellm_data }

      expect(t2).to be < (t1 / 10.0)
    end
  end
end
```

### Adapter integration specs

```ruby
RSpec.describe RubyLLM::Agents::Pricing::PortkeyAdapter, :integration do
  describe ".find_model" do
    it "returns normalized pricing for gpt-4o" do
      result = described_class.find_model("gpt-4o")
      expect(result[:input_cost_per_token]).to be > 0
      expect(result[:output_cost_per_token]).to be > 0
      expect(result[:source]).to eq(:portkey)
    end

    it "returns audio token pricing for whisper-1" do
      result = described_class.find_model("whisper-1")
      expect(result[:input_cost_per_audio_token]).to be > 0
      expect(result[:source]).to eq(:portkey)
    end

    it "returns nil for unknown models" do
      result = described_class.find_model("totally-fake-model-xyz")
      expect(result).to be_nil
    end
  end
end

RSpec.describe RubyLLM::Agents::Pricing::HeliconeAdapter, :integration do
  describe ".find_model" do
    it "returns normalized pricing for gpt-4o" do
      result = described_class.find_model("gpt-4o")
      expect(result[:input_cost_per_token]).to be > 0
      expect(result[:source]).to eq(:helicone)
    end

    it "returns nil for transcription models (not in Helicone)" do
      result = described_class.find_model("whisper-1")
      expect(result).to be_nil
    end
  end
end

RSpec.describe RubyLLM::Agents::Pricing::LLMPricingAdapter, :integration do
  describe ".find_model" do
    it "returns normalized pricing for gpt-4o" do
      result = described_class.find_model("gpt-4o")
      expect(result[:input_cost_per_token]).to be > 0
      expect(result[:source]).to eq(:llmpricing)
    end

    it "returns nil for non-covered models" do
      result = described_class.find_model("whisper-1")
      expect(result).to be_nil
    end
  end
end
```

### End-to-end transcription pricing integration spec

```ruby
RSpec.describe RubyLLM::Agents::Audio::TranscriptionPricing, :integration do
  before do
    RubyLLM::Agents.reset_configuration!
    described_class.refresh!
  end

  describe ".cost_per_minute" do
    it "finds pricing for whisper-1" do
      price = described_class.cost_per_minute("whisper-1")
      expect(price).to be > 0
      expect(price).to be < 1  # sanity: less than $1/min
    end

    it "finds pricing for gpt-4o-transcribe" do
      price = described_class.cost_per_minute("gpt-4o-transcribe")
      expect(price).to be > 0
    end

    it "finds pricing for gpt-4o-mini-transcribe" do
      price = described_class.cost_per_minute("gpt-4o-mini-transcribe")
      expect(price).to be > 0
    end

    it "finds pricing for groq/whisper-large-v3" do
      price = described_class.cost_per_minute("groq/whisper-large-v3")
      expect(price).to be > 0
    end

    it "finds pricing for deepgram/nova-3" do
      price = described_class.cost_per_minute("deepgram/nova-3")
      expect(price).to be > 0
    end

    it "returns nil for unknown models" do
      expect(described_class.cost_per_minute("fake-model-xyz")).to be_nil
    end
  end

  describe "user config takes priority over all API sources" do
    it "returns user price even when APIs disagree" do
      RubyLLM::Agents.configure do |c|
        c.transcription_model_pricing = { "whisper-1" => 0.999 }
      end
      expect(described_class.cost_per_minute("whisper-1")).to eq(0.999)
    end
  end

  describe ".all_pricing" do
    it "returns data from all sources" do
      pricing = described_class.all_pricing
      expect(pricing.keys).to include(:litellm, :portkey, :openrouter, :helicone, :configured)
    end
  end
end
```

### What the integration tests verify

1. **API availability** — Each source endpoint responds with valid JSON
2. **Schema stability** — Expected fields exist in responses
3. **Known model coverage** — whisper-1, gpt-4o, claude, etc. are found
4. **Price sanity** — Prices are positive, within reasonable bounds
5. **Cross-source cascade** — If one source misses, another catches
6. **Caching performance** — Second call is 10x+ faster
7. **User config priority** — Config always wins

### Existing unit tests (kept, use WebMock)

The current specs that use `stub_request` remain for fast CI. They test cascade logic, nil handling, cache expiration, and config priority without network calls.

---

## Implementation Order

### Phase 1: Shared DataStore + LiteLLM adapter
1. Create `Pricing::DataStore` with HTTP fetch + two-layer cache
2. Create `Pricing::LiteLLMAdapter` extracted from current code
3. Enhance LiteLLM extraction: add `input_cost_per_audio_token` pattern (8 GPT-4o-transcribe models)
4. Refactor `TranscriptionPricing` to use `DataStore` + `LiteLLMAdapter`
5. Verify all 4000+ existing specs pass

### Phase 2: Portkey adapter
1. Create `Pricing::PortkeyAdapter` with provider resolution + unit conversion
2. Add Portkey as fallback tier in `TranscriptionPricing`
3. Add config attrs (`portkey_pricing_enabled`, `portkey_pricing_url`)
4. Write integration tests

### Phase 3: OpenRouter adapter
1. Create `Pricing::OpenRouterAdapter` with model matching + price normalization
2. Add as fallback tier in `TranscriptionPricing`
3. Add config attrs (`openrouter_pricing_enabled`, `openrouter_pricing_url`)
4. Write integration tests

### Phase 4: Helicone adapter
1. Create `Pricing::HeliconeAdapter` with model matching
2. Add as fallback tier (text LLM pricing primarily)
3. Add config attrs (`helicone_pricing_enabled`, `helicone_pricing_url`)
4. Write integration tests

### Phase 5: LLM Pricing AI adapter
1. Create `Pricing::LLMPricingAdapter` with provider mapping
2. Add as last-resort fallback (text LLM only)
3. Add config attr (`llmpricing_enabled`, `llmpricing_url`)
4. Write integration tests

### Phase 6: Apply to SpeechPricing + ImagePricing
1. Refactor `SpeechPricing` to use shared adapters (keep ElevenLabs tier)
2. Refactor `ImageGenerator::Pricing` to use shared adapters (keep hardcoded fallbacks for now)
3. All three pricing modules now benefit from 5 sources
4. Update integration tests

### Phase 7: Dashboard + observability
1. Store `pricing_source` in execution metadata (e.g., "litellm", "portkey")
2. Show source badge on execution detail page
3. Optional: `/pricing` debug page showing `all_pricing` from all sources with cache stats

---

## Risk Considerations

| Risk | Mitigation |
|------|-----------|
| API rate limiting | 24h cache TTL; bulk fetch preferred; lazy cascade (don't call later sources if earlier one hits) |
| API schema changes | Defensive `.dig()` access; graceful nil returns; integration tests catch regressions early |
| Portkey unit ambiguity | Cross-validate against LiteLLM + OpenAI published prices in integration tests; configurable conversion factors |
| OpenRouter price strings | `.to_f` conversion; reject `0.0` values |
| LLM Pricing AI limitations | Only 79 models across 4 providers; lowest priority; graceful nil |
| Slow integration tests | Tag `:integration`; exclude from default CI; run on schedule or pre-release |
| Large LiteLLM JSON (~2MB) | Already cached; consider streaming JSON parse for memory-constrained envs |
| Cold start latency | Lazy fetching means only the first source that hits is fetched; background prefetch via `after_initialize` optional |
| Multiple modules sharing DataStore state | Thread-safe via `Mutex` on cache writes; in-memory cache is process-local |

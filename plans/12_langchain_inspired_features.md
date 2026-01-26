# LangChain-Inspired Features Plan

## Overview

This plan outlines features inspired by LangChain/LangGraph that would enhance ruby_llm-agents. After analyzing both frameworks, we've identified four key areas where LangChain patterns could improve our library while maintaining Ruby/Rails idioms.

---

## Goals

1. **Smarter Memory Management** - Multiple conversation memory strategies to handle long conversations
2. **RAG Pipeline** - First-class retrieval-augmented generation support
3. **Typed Workflow State** - Explicit state schemas for predictable workflows
4. **Checkpoint & Time Travel** - Branch and replay workflow executions

> **Note**: Some LangChain features are intentionally excluded:
> - **Output Parsers** - Ruby_llm-agents already supports provider-enforced structured output via `RubyLLM::Schema`
> - **Prompt Templates** - The existing `system_prompt` and `user_prompt` methods provide full Ruby flexibility (conditionals, loops, interpolation) which is more powerful than template DSLs

---

## Feature 1: Memory Systems

### Problem

Currently, agents receive raw `messages` arrays. For long conversations, this leads to:
- Context overflow (exceeding token limits)
- High costs (paying for full history every call)
- No summarization of old context

### LangChain Approach

LangChain offers multiple memory types:
- `ConversationBufferMemory` - Store all messages (current behavior)
- `ConversationBufferWindowMemory` - Keep only last K messages
- `ConversationSummaryMemory` - Summarize old messages with LLM
- `ConversationTokenBufferMemory` - Manage by token count
- `ConversationSummaryBufferMemory` - Hybrid: summary + recent buffer

### Proposed Design

#### DSL

```ruby
class CustomerSupportAgent < ApplicationAgent
  model "gpt-4o"

  # Memory strategies
  memory :buffer                           # Default: keep all messages
  memory :window, size: 10                 # Keep last 10 exchanges
  memory :summary, model: "gpt-4o-mini"    # Summarize old context
  memory :token_buffer, max_tokens: 4000   # Manage by token count
  memory :hybrid, window: 5, summary: true # Recent + summary

  # Custom memory class
  memory CustomMemory, **options
end
```

#### Memory Classes

```ruby
module RubyLLM
  module Agents
    module Memory
      class Base
        def initialize(messages, **options)
          @messages = messages
          @options = options
        end

        # Returns processed messages for LLM
        def process
          raise NotImplementedError
        end

        # Token count helper
        def token_count(messages)
          messages.sum { |m| estimate_tokens(m[:content]) }
        end
      end

      class Buffer < Base
        def process
          @messages # Return all messages unchanged
        end
      end

      class Window < Base
        def process
          size = @options[:size] || 10
          return @messages if @messages.size <= size * 2

          # Keep system message + last N exchanges
          system = @messages.select { |m| m[:role] == "system" }
          exchanges = @messages.reject { |m| m[:role] == "system" }

          system + exchanges.last(size * 2)
        end
      end

      class Summary < Base
        def process
          return @messages if @messages.size <= threshold

          # Split into old and recent
          system = @messages.select { |m| m[:role] == "system" }
          exchanges = @messages.reject { |m| m[:role] == "system" }

          old_messages = exchanges[0...-recent_count]
          recent_messages = exchanges[-recent_count..]

          # Summarize old messages
          summary = summarize(old_messages)

          system + [{ role: "system", content: "Previous conversation summary:\n#{summary}" }] + recent_messages
        end

        private

        def summarize(messages)
          SummaryAgent.call(
            messages: messages,
            model: @options[:model] || "gpt-4o-mini"
          ).content
        end

        def threshold
          @options[:threshold] || 20
        end

        def recent_count
          @options[:recent] || 6
        end
      end

      class TokenBuffer < Base
        def process
          max_tokens = @options[:max_tokens] || 4000
          return @messages if token_count(@messages) <= max_tokens

          system = @messages.select { |m| m[:role] == "system" }
          exchanges = @messages.reject { |m| m[:role] == "system" }

          # Keep removing oldest until under limit
          while token_count(system + exchanges) > max_tokens && exchanges.size > 2
            exchanges.shift
          end

          system + exchanges
        end
      end

      class Hybrid < Base
        def process
          window_size = @options[:window] || 5

          system = @messages.select { |m| m[:role] == "system" }
          exchanges = @messages.reject { |m| m[:role] == "system" }

          return @messages if exchanges.size <= window_size * 2

          old_messages = exchanges[0...-window_size * 2]
          recent_messages = exchanges[-window_size * 2..]

          if @options[:summary]
            summary = Memory::Summary.new(old_messages, model: @options[:summary_model]).summarize(old_messages)
            system + [{ role: "system", content: "Previous conversation summary:\n#{summary}" }] + recent_messages
          else
            system + recent_messages
          end
        end
      end
    end
  end
end
```

#### Integration with BaseAgent

```ruby
class BaseAgent
  class << self
    def memory(strategy = :buffer, **options)
      if strategy.is_a?(Class)
        @memory_class = strategy
        @memory_options = options
      else
        @memory_class = Memory.const_get(strategy.to_s.camelize)
        @memory_options = options
      end
    end

    def memory_class
      @memory_class || Memory::Buffer
    end

    def memory_options
      @memory_options || {}
    end
  end

  private

  def processed_messages
    return messages unless messages.present?

    memory = self.class.memory_class.new(messages, **self.class.memory_options)
    memory.process
  end
end
```

### Files to Create

```
lib/ruby_llm/agents/memory/
├── base.rb
├── buffer.rb
├── window.rb
├── summary.rb
├── token_buffer.rb
├── hybrid.rb
└── entity.rb (future: track entities across conversation)
```

### Files to Modify

- `lib/ruby_llm/agents/base_agent.rb` - Add memory DSL and processing
- `lib/ruby_llm/agents/dsl/base.rb` - Add memory class method

---

## Feature 2: RAG Pipeline

### Problem

Users want to build knowledge-based agents but must manually:
1. Load documents
2. Chunk text
3. Generate embeddings
4. Store in vector database
5. Query similar content
6. Inject into prompt

### LangChain Approach

LangChain provides:
- Document loaders (PDF, web, CSV, etc.)
- Text splitters (character, token, recursive)
- Vector stores (Pinecone, Chroma, Postgres/pgvector)
- Retrievers (similarity, MMR, self-query)

### Proposed Design

#### RAG Components

```ruby
module RubyLLM
  module Agents
    module RAG
      # Document loading
      class Document
        attr_accessor :content, :metadata

        def initialize(content:, metadata: {})
          @content = content
          @metadata = metadata
        end
      end

      # Document loaders
      module Loaders
        class PDF
          def load(path)
            # Extract text from PDF
          end
        end

        class Web
          def load(url)
            # Fetch and parse HTML
          end
        end

        class Directory
          def load(path, glob: "**/*.{txt,md}")
            # Load all matching files
          end
        end
      end

      # Text splitters
      module Splitters
        class Character
          def initialize(chunk_size: 1000, overlap: 200, separator: "\n\n")
            @chunk_size = chunk_size
            @overlap = overlap
            @separator = separator
          end

          def split(text)
            # Split text into overlapping chunks
          end
        end

        class Token
          def initialize(chunk_size: 500, overlap: 50, model: "gpt-4o")
            @chunk_size = chunk_size
            @overlap = overlap
            @model = model
          end

          def split(text)
            # Split by token count
          end
        end

        class Recursive
          def initialize(chunk_size: 1000, separators: ["\n\n", "\n", " ", ""])
            @chunk_size = chunk_size
            @separators = separators
          end

          def split(text)
            # Recursively split with multiple separators
          end
        end
      end

      # Vector stores
      module Stores
        class Base
          def add(documents, embedder:)
            raise NotImplementedError
          end

          def search(query, embedder:, k: 5)
            raise NotImplementedError
          end

          def delete(ids)
            raise NotImplementedError
          end
        end

        class Pgvector < Base
          def initialize(table_name: "rag_documents", connection: ActiveRecord::Base)
            @table_name = table_name
            @connection = connection
          end

          def add(documents, embedder:)
            documents.each do |doc|
              vector = embedder.call(input: doc.content).vector
              @connection.execute(<<~SQL)
                INSERT INTO #{@table_name} (content, metadata, embedding)
                VALUES (#{doc.content}, #{doc.metadata.to_json}, #{vector})
              SQL
            end
          end

          def search(query, embedder:, k: 5)
            query_vector = embedder.call(input: query).vector

            @connection.execute(<<~SQL)
              SELECT content, metadata, embedding <=> '#{query_vector}' as distance
              FROM #{@table_name}
              ORDER BY distance
              LIMIT #{k}
            SQL
          end
        end

        class InMemory < Base
          def initialize
            @documents = []
            @embeddings = []
          end

          def add(documents, embedder:)
            documents.each do |doc|
              @documents << doc
              @embeddings << embedder.call(input: doc.content).vector
            end
          end

          def search(query, embedder:, k: 5)
            query_vector = embedder.call(input: query).vector

            distances = @embeddings.map { |emb| cosine_distance(query_vector, emb) }
            indices = distances.each_with_index.sort_by(&:first).take(k).map(&:last)

            indices.map { |i| @documents[i] }
          end

          private

          def cosine_distance(a, b)
            dot = a.zip(b).sum { |x, y| x * y }
            mag_a = Math.sqrt(a.sum { |x| x * x })
            mag_b = Math.sqrt(b.sum { |x| x * x })
            1 - (dot / (mag_a * mag_b))
          end
        end
      end

      # Retriever that combines everything
      class Retriever
        attr_reader :store, :embedder, :splitter

        def initialize(store:, embedder:, splitter: nil)
          @store = store
          @embedder = embedder
          @splitter = splitter || Splitters::Recursive.new
        end

        def add_documents(documents)
          chunks = documents.flat_map { |doc| split_document(doc) }
          @store.add(chunks, embedder: @embedder)
        end

        def retrieve(query, k: 5)
          @store.search(query, embedder: @embedder, k: k)
        end

        private

        def split_document(doc)
          chunks = @splitter.split(doc.content)
          chunks.map do |chunk|
            Document.new(
              content: chunk,
              metadata: doc.metadata.merge(chunk: true)
            )
          end
        end
      end
    end
  end
end
```

#### RAG Agent Base Class

```ruby
class RAGAgent < BaseAgent
  class << self
    def retriever(retriever = nil, &block)
      if block_given?
        @retriever_builder = block
      else
        @retriever = retriever
      end
    end

    def retriever_instance
      @retriever ||= @retriever_builder&.call
    end

    def context_limit(limit)
      @context_limit = limit
    end
  end

  param :query, required: true

  def system_prompt
    context = retrieve_context

    <<~PROMPT
      Answer the user's question based on the following context.
      If the context doesn't contain relevant information, say so.

      Context:
      #{context}
    PROMPT
  end

  def user_prompt
    query
  end

  private

  def retrieve_context
    return "" unless self.class.retriever_instance

    documents = self.class.retriever_instance.retrieve(query, k: context_k)
    documents.map(&:content).join("\n\n---\n\n")
  end

  def context_k
    self.class.instance_variable_get(:@context_limit) || 5
  end
end
```

#### Usage Example

```ruby
# Setup retriever once
class KnowledgeRetriever
  def self.instance
    @instance ||= begin
      store = RubyLLM::Agents::RAG::Stores::Pgvector.new(table_name: "knowledge_base")
      embedder = DocumentEmbedder # Your embedder agent

      RubyLLM::Agents::RAG::Retriever.new(
        store: store,
        embedder: embedder,
        splitter: RubyLLM::Agents::RAG::Splitters::Recursive.new(chunk_size: 500)
      )
    end
  end
end

# Define RAG agent
class KnowledgeAgent < RubyLLM::Agents::RAGAgent
  model "gpt-4o"

  retriever { KnowledgeRetriever.instance }
  context_limit 10

  def system_prompt
    <<~PROMPT
      You are a helpful assistant for our product documentation.

      Use the following documentation to answer questions:
      #{retrieve_context}

      If you can't find the answer in the documentation, say so clearly.
    PROMPT
  end
end

# Use it
result = KnowledgeAgent.call(query: "How do I configure webhooks?")
```

### Files to Create

```
lib/ruby_llm/agents/rag/
├── document.rb
├── loaders/
│   ├── base.rb
│   ├── pdf.rb
│   ├── web.rb
│   └── directory.rb
├── splitters/
│   ├── base.rb
│   ├── character.rb
│   ├── token.rb
│   └── recursive.rb
├── stores/
│   ├── base.rb
│   ├── pgvector.rb
│   ├── in_memory.rb
│   └── pinecone.rb (future)
├── retriever.rb
└── rag_agent.rb
```

---

## Feature 3: Typed Workflow State

### Problem

Workflow state is implicit and untyped. Complex workflows become hard to debug because:
- State shape is unclear
- No validation of state transitions
- Hard to know what data is available at each step

### LangGraph Approach

LangGraph uses typed state schemas with reducers:

```python
class State(TypedDict):
    messages: Annotated[list[str], add]  # Reducer: append
    summary: str
    step_count: int
```

### Proposed Design

#### State Schema DSL

```ruby
class OrderWorkflow < RubyLLM::Agents::Workflow
  # Typed state schema
  state do
    field :order_id, String, required: true
    field :customer, Hash, default: {}
    field :items, Array, default: [], reducer: :append
    field :total, Float, default: 0.0, reducer: :sum
    field :status, String, default: "pending"
    field :errors, Array, default: [], reducer: :append
    field :metadata, Hash, default: {}, reducer: :merge
  end

  # Steps can read/write typed state
  step :validate do
    state.order_id  # => "123" (typed access)

    # Update state (validated)
    update_state(status: "validated", metadata: { validated_at: Time.current })
  end

  step :process, ProcessorAgent,
       input: -> { { order_id: state.order_id, items: state.items } }

  step :finalize do
    # Append to array field (uses reducer)
    append_state(:items, { id: "new-item", price: 10.0 })

    # Type error if wrong type
    update_state(total: "invalid")  # Raises StateTypeError
  end
end
```

#### State Schema Implementation

```ruby
module RubyLLM
  module Agents
    class Workflow
      class StateSchema
        attr_reader :fields

        def initialize
          @fields = {}
        end

        def field(name, type, required: false, default: nil, reducer: nil)
          @fields[name] = {
            type: type,
            required: required,
            default: default,
            reducer: reducer
          }
        end

        def validate!(state)
          @fields.each do |name, config|
            value = state[name]

            if config[:required] && value.nil?
              raise StateValidationError, "Required field #{name} is missing"
            end

            if value && !value.is_a?(config[:type])
              raise StateTypeError, "Field #{name} expected #{config[:type]}, got #{value.class}"
            end
          end
        end

        def with_defaults
          @fields.transform_values { |config| config[:default] }
        end

        def apply_reducer(field_name, current_value, new_value)
          config = @fields[field_name]
          reducer = config&.dig(:reducer)

          case reducer
          when :append
            (current_value || []) + Array(new_value)
          when :merge
            (current_value || {}).merge(new_value || {})
          when :sum
            (current_value || 0) + (new_value || 0)
          when :replace, nil
            new_value
          when Proc
            reducer.call(current_value, new_value)
          else
            raise "Unknown reducer: #{reducer}"
          end
        end
      end

      class TypedState
        def initialize(schema, initial_values = {})
          @schema = schema
          @data = schema.with_defaults.merge(initial_values)
          @schema.validate!(@data)
        end

        def [](key)
          @data[key]
        end

        def update(updates)
          updates.each do |key, value|
            @data[key] = @schema.apply_reducer(key, @data[key], value)
          end
          @schema.validate!(@data)
          self
        end

        def to_h
          @data.dup
        end

        def method_missing(method, *args)
          if @data.key?(method)
            @data[method]
          elsif method.to_s.end_with?("=") && @data.key?(method.to_s.chomp("=").to_sym)
            key = method.to_s.chomp("=").to_sym
            @data[key] = @schema.apply_reducer(key, @data[key], args.first)
          else
            super
          end
        end

        def respond_to_missing?(method, include_private = false)
          @data.key?(method) || @data.key?(method.to_s.chomp("=").to_sym) || super
        end
      end

      # DSL class method
      class << self
        def state(&block)
          @state_schema = StateSchema.new
          @state_schema.instance_eval(&block)
          @state_schema
        end

        def state_schema
          @state_schema
        end
      end
    end
  end
end
```

### Files to Create

```
lib/ruby_llm/agents/workflow/
├── state_schema.rb
├── typed_state.rb
└── state_errors.rb
```

### Files to Modify

- `lib/ruby_llm/agents/workflow/orchestrator.rb` - Use typed state
- `lib/ruby_llm/agents/workflow/dsl.rb` - Add state DSL

---

## Feature 4: Checkpoint & Time Travel

### Problem

When workflows fail midway:
- Must restart from beginning
- Can't inspect intermediate state
- Can't branch to try different approaches

### LangGraph Approach

LangGraph provides:
- Checkpointing after each node
- Time travel to any checkpoint
- Branching from checkpoints
- Human-in-the-loop with state inspection

### Proposed Design

#### Checkpoint System

```ruby
module RubyLLM
  module Agents
    class Workflow
      module Checkpointing
        extend ActiveSupport::Concern

        class_methods do
          def checkpointing(enabled: true, store: :database)
            @checkpointing_enabled = enabled
            @checkpoint_store = store
          end

          def checkpointing_enabled?
            @checkpointing_enabled != false
          end

          def checkpoint_store
            @checkpoint_store || :database
          end
        end

        def checkpoint!(step_name, state)
          return unless self.class.checkpointing_enabled?

          Checkpoint.create!(
            workflow_id: workflow_id,
            workflow_type: self.class.name,
            step_name: step_name,
            state: state.to_h,
            step_results: @step_results.transform_values(&:to_h),
            created_at: Time.current
          )
        end

        def restore_from_checkpoint(checkpoint_id)
          checkpoint = Checkpoint.find(checkpoint_id)

          @state = TypedState.new(self.class.state_schema, checkpoint.state)
          @step_results = checkpoint.step_results.transform_values { |h| StepResult.from_h(h) }
          @current_step_index = find_step_index(checkpoint.step_name) + 1

          self
        end

        def branch_from_checkpoint(checkpoint_id, **state_overrides)
          checkpoint = Checkpoint.find(checkpoint_id)

          new_workflow = self.class.new(**@input)
          new_workflow.instance_variable_set(:@workflow_id, SecureRandom.uuid)
          new_workflow.instance_variable_set(:@parent_checkpoint_id, checkpoint_id)

          state = checkpoint.state.merge(state_overrides)
          new_workflow.instance_variable_set(:@state, TypedState.new(self.class.state_schema, state))
          new_workflow.instance_variable_set(:@step_results, checkpoint.step_results.dup)
          new_workflow.instance_variable_set(:@current_step_index, find_step_index(checkpoint.step_name) + 1)

          new_workflow
        end
      end

      # Checkpoint model
      class Checkpoint < ActiveRecord::Base
        self.table_name = "ruby_llm_agents_workflow_checkpoints"

        serialize :state, coder: JSON
        serialize :step_results, coder: JSON

        belongs_to :execution, class_name: "RubyLLM::Agents::Execution", optional: true

        scope :for_workflow, ->(workflow_id) { where(workflow_id: workflow_id) }
        scope :recent, -> { order(created_at: :desc) }

        def self.latest_for(workflow_id)
          for_workflow(workflow_id).recent.first
        end
      end
    end
  end
end
```

#### Time Travel API

```ruby
# Get workflow history
checkpoints = RubyLLM::Agents::Workflow::Checkpoint.for_workflow(workflow_id)

# Inspect checkpoint state
checkpoint = checkpoints.find_by(step_name: "validate")
checkpoint.state       # => { order_id: "123", status: "validated" }
checkpoint.step_results # => { fetch: { content: "...", cost: 0.01 } }

# Resume from checkpoint
workflow = OrderWorkflow.resume(checkpoint.id)
result = workflow.call

# Branch from checkpoint with modified state
workflow = OrderWorkflow.branch_from(checkpoint.id, status: "priority")
result = workflow.call  # Runs from checkpoint with new state

# Time travel: replay with different input
workflow = OrderWorkflow.replay(
  checkpoint_id: checkpoint.id,
  modify_step: :validate,
  with_input: { force_validation: true }
)
```

#### DSL Integration

```ruby
class OrderWorkflow < RubyLLM::Agents::Workflow
  checkpointing enabled: true, store: :database

  # Checkpoint after specific steps
  step :validate, ValidatorAgent, checkpoint: true
  step :process, ProcessorAgent  # No checkpoint (inherits default)
  step :finalize, checkpoint: true

  # Or checkpoint all steps
  checkpoint_all_steps true
end
```

### Files to Create

```
lib/ruby_llm/agents/workflow/
├── checkpointing.rb
├── checkpoint.rb (ActiveRecord model)
└── time_travel.rb

db/migrate/
└── create_workflow_checkpoints.rb
```

---

## Implementation Phases

### Phase 1: Memory Systems (Foundation)
- [ ] Create memory base class and strategies
- [ ] Add memory DSL to BaseAgent
- [ ] Implement Buffer, Window, TokenBuffer
- [ ] Implement Summary memory (requires internal agent call)
- [ ] Tests for all memory types
- [ ] Documentation

### Phase 2: Typed Workflow State
- [ ] Create StateSchema class
- [ ] Create TypedState class
- [ ] Add state DSL to Workflow
- [ ] Implement reducers
- [ ] Update orchestrator to use typed state
- [ ] Tests and documentation

### Phase 3: Checkpointing & Time Travel
- [ ] Create Checkpoint model and migration
- [ ] Implement checkpoint saving after steps
- [ ] Implement restore_from_checkpoint
- [ ] Implement branch_from_checkpoint
- [ ] Add checkpoint DSL options
- [ ] Dashboard integration (view checkpoints)
- [ ] Tests and documentation

### Phase 4: RAG Pipeline
- [ ] Create Document class
- [ ] Implement text splitters
- [ ] Implement in-memory vector store
- [ ] Implement pgvector store
- [ ] Create Retriever class
- [ ] Create RAGAgent base class
- [ ] Tests and documentation

---

## Priority Order

Based on value and complexity:

| Feature | Value | Complexity | Priority |
|---------|-------|------------|----------|
| Memory Systems | High | Medium | 1 |
| Typed Workflow State | Medium | Medium | 2 |
| Checkpointing | Medium | High | 3 |
| RAG Pipeline | High | High | 4 |

---

## Success Criteria

1. **Memory**: Long conversations work without context overflow
2. **State**: Workflow state is typed, validated, and predictable
3. **Checkpoints**: Failed workflows can resume from any step
4. **RAG**: Document-based agents work out of the box

---

## Open Questions

1. **Memory persistence**: Should memory strategies persist across sessions?
   - Could store in Redis or database
   - Useful for long-running conversations

2. **RAG store choice**: Should we bundle pgvector support or keep it optional?
   - Bundling increases gem size
   - Optional requires user setup

3. **Checkpoint storage**: Database vs Redis vs custom store?
   - Database is simplest for Rails users
   - Redis is faster for high-throughput

4. **State schema validation**: Runtime only or also static analysis?
   - Runtime is simpler
   - Static could catch errors earlier

---

## Comparison: Before & After

### Memory Management

**Before:**
```ruby
# Manual message management
messages = conversation.messages.last(20)  # Hope this is enough
result = ChatAgent.call(messages: messages)
```

**After:**
```ruby
class ChatAgent < ApplicationAgent
  memory :hybrid, window: 10, summary: true
end

# Automatic context management
result = ChatAgent.call(messages: conversation.all_messages)
```

### Workflow State

**Before:**
```ruby
# Implicit state, easy to break
step :process do
  # What fields exist? No idea without reading all steps
  result = fetch.content
  { processed: transform(result) }
end
```

**After:**
```ruby
state do
  field :order_id, String, required: true
  field :items, Array, default: [], reducer: :append
end

step :process do
  # Typed access, validated updates
  state.order_id      # Type-safe access
  update_state(items: new_item)  # Validated, uses reducer
end
```

---

## Files Summary

### Create

```
lib/ruby_llm/agents/
├── memory/
│   ├── base.rb
│   ├── buffer.rb
│   ├── window.rb
│   ├── summary.rb
│   ├── token_buffer.rb
│   └── hybrid.rb
├── rag/
│   ├── document.rb
│   ├── loaders/
│   ├── splitters/
│   ├── stores/
│   └── retriever.rb
├── workflow/
│   ├── state_schema.rb
│   ├── typed_state.rb
│   ├── checkpointing.rb
│   └── checkpoint.rb

db/migrate/
└── create_workflow_checkpoints.rb

spec/
├── memory/
├── rag/
└── workflow/state_spec.rb
```

### Modify

```
lib/ruby_llm/agents/
├── base_agent.rb (memory DSL)
├── dsl/base.rb (memory class method)
├── workflow/dsl.rb (state DSL)
└── workflow/orchestrator.rb (typed state, checkpointing)
```

---

## References

- [LangChain Python Docs](https://docs.langchain.com/oss/python/langchain/overview)
- [LangGraph Concepts](https://docs.langchain.com/langgraph)
- [LangChain Memory Types](https://docs.langchain.com/oss/python/integrations/memory)
- [LangGraph Checkpointing](https://docs.langchain.com/oss/python/langgraph/persistence)

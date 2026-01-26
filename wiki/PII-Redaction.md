# PII Redaction

Automatically protect sensitive data in execution logs and prompts.

## Quick Setup

```ruby
# config/initializers/ruby_llm_agents.rb
RubyLLM::Agents.configure do |config|
  config.redaction = {
    fields: %w[ssn credit_card phone_number],
    patterns: [
      /\b\d{3}-\d{2}-\d{4}\b/,  # SSN
      /\b\d{16}\b/              # Credit card
    ],
    placeholder: "[REDACTED]"
  }
end
```

## Default Redacted Fields

These field names are redacted by default:

- `password`
- `token`
- `api_key`
- `secret`
- `credential`
- `auth`
- `key`
- `access_token`

## Configuration Options

### Field-Based Redaction

Redact values by parameter name:

```ruby
config.redaction = {
  fields: %w[
    ssn
    social_security
    credit_card
    card_number
    cvv
    phone
    phone_number
    email
    address
    birth_date
    passport
  ]
}
```

### Pattern-Based Redaction

Redact values matching regex patterns:

```ruby
config.redaction = {
  patterns: [
    # US Social Security Number
    /\b\d{3}-\d{2}-\d{4}\b/,

    # Credit Card Numbers
    /\b\d{4}[\s-]?\d{4}[\s-]?\d{4}[\s-]?\d{4}\b/,

    # Phone Numbers (US)
    /\b\d{3}[-.]?\d{3}[-.]?\d{4}\b/,

    # Email Addresses
    /\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b/i,

    # IP Addresses
    /\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b/
  ]
}
```

### Placeholder Text

Customize the redaction placeholder:

```ruby
config.redaction = {
  placeholder: "[REDACTED]"
  # or
  placeholder: "***"
  # or
  placeholder: "[PII REMOVED]"
}
```

### Value Truncation

Limit stored value length:

```ruby
config.redaction = {
  max_value_length: 1000  # Truncate values over 1000 chars
}
```

## Persistence Control

### Disable Prompt Storage

```ruby
config.persist_prompts = false  # Don't store prompts in database
config.persist_responses = true # Still store responses
```

### Disable Response Storage

```ruby
config.persist_prompts = true
config.persist_responses = false  # Don't store LLM responses
```

### Disable Both

```ruby
# For maximum privacy
config.persist_prompts = false
config.persist_responses = false
```

## What Gets Redacted

### Parameters

```ruby
class MyAgent < ApplicationAgent
  param :user_email, required: true
  param :credit_card, required: true
end

MyAgent.call(
  user_email: "john@example.com",
  credit_card: "4111111111111111"
)

# In execution record:
execution.parameters
# => { "user_email" => "[REDACTED]", "credit_card" => "[REDACTED]" }
```

### Prompts

```ruby
def user_prompt
  "Process payment for card #{credit_card}"
end

# Stored as:
# "Process payment for card [REDACTED]"
```

### Responses

```ruby
# LLM response contains:
# "User's SSN is 123-45-6789"

# Stored as:
# "User's SSN is [REDACTED]"
```

## Custom Redaction Logic

### Per-Agent Redaction

```ruby
class SensitiveAgent < ApplicationAgent
  param :ssn, required: true

  def execution_metadata
    {
      ssn_provided: true,
      # Don't include actual SSN
    }
  end

  # Override parameter sanitization
  def sanitized_parameters
    super.merge(ssn: mask_ssn(ssn))
  end

  private

  def mask_ssn(ssn)
    "XXX-XX-#{ssn[-4..]}"  # Show only last 4
  end
end
```

### Conditional Redaction

```ruby
config.redaction = {
  custom: ->(field, value, context) {
    if field == "email" && context[:internal_user]
      value  # Don't redact internal emails
    else
      "[REDACTED]"
    end
  }
}
```

## Compliance Considerations

### GDPR

```ruby
config.redaction = {
  # Redact all personal identifiers
  fields: %w[
    name email phone address ip_address
    user_id customer_id
  ],
  patterns: [
    /\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b/i
  ]
}

# Don't persist raw data
config.persist_prompts = false
config.persist_responses = false
config.retention_period = 30.days
```

### HIPAA

```ruby
config.redaction = {
  fields: %w[
    patient_id medical_record mrn
    ssn dob phone address
    insurance_id policy_number
  ],
  patterns: [
    /\b\d{3}-\d{2}-\d{4}\b/,  # SSN
    /MRN:\s*\d+/i,            # Medical record numbers
  ]
}
```

### PCI-DSS

```ruby
config.redaction = {
  fields: %w[
    card_number pan cvv cvc
    expiration_date cardholder_name
    account_number routing_number
  ],
  patterns: [
    /\b\d{4}[\s-]?\d{4}[\s-]?\d{4}[\s-]?\d{4}\b/,  # Card numbers
    /\b\d{3,4}\b/  # CVV (context-aware)
  ]
}
```

## Viewing Redacted Data

### In Dashboard

Redacted values show as `[REDACTED]` in:
- Execution detail view
- Parameter display
- Prompt/response views

### Audit Logging

```ruby
# Log redaction events
config.redaction = {
  on_redact: ->(field, original_length) {
    Rails.logger.info("Redacted #{field} (#{original_length} chars)")
  }
}
```

## Testing Redaction

```ruby
RSpec.describe "PII Redaction" do
  it "redacts SSN from parameters" do
    LLM::MyAgent.call(ssn: "123-45-6789", query: "test")

    execution = RubyLLM::Agents::Execution.last
    expect(execution.parameters["ssn"]).to eq("[REDACTED]")
  end

  it "redacts patterns from prompts" do
    LLM::MyAgent.call(message: "My SSN is 123-45-6789")

    execution = RubyLLM::Agents::Execution.last
    expect(execution.user_prompt).not_to include("123-45-6789")
    expect(execution.user_prompt).to include("[REDACTED]")
  end
end
```

## Best Practices

### Redact Broadly, Not Narrowly

```ruby
# Good: Comprehensive redaction
fields: %w[ssn social_security tax_id ein]

# Risky: Too narrow
fields: %w[ssn]  # Misses "social_security_number"
```

### Test Your Patterns

```ruby
# Verify patterns work
pattern = /\b\d{3}-\d{2}-\d{4}\b/
test_values = ["123-45-6789", "SSN: 123-45-6789", "no match"]
test_values.each do |val|
  puts "#{val}: #{val.gsub(pattern, '[REDACTED]')}"
end
```

### Don't Rely Solely on Redaction

```ruby
# Defense in depth:
# 1. Redaction (logs)
# 2. Encryption (storage)
# 3. Access control (who can view)
# 4. Retention limits (auto-delete)

config.redaction = { fields: [...] }
config.retention_period = 30.days
```

### Document What's Redacted

```ruby
# In your security documentation:
# - SSN: Fully redacted
# - Email: Fully redacted
# - Phone: Fully redacted
# - User ID: Preserved for debugging
```

## Troubleshooting

### Pattern Not Matching

```ruby
# Debug patterns
value = "My SSN is 123-45-6789"
pattern = /\b\d{3}-\d{2}-\d{4}\b/

if value.match?(pattern)
  puts "Pattern matches: #{value.gsub(pattern, '[REDACTED]')}"
else
  puts "Pattern doesn't match"
end
```

### Field Not Redacted

```ruby
# Check field name exactly matches
config.redaction = {
  fields: %w[credit_card]  # Must match parameter name exactly
}

# If parameter is "creditCard" (camelCase), add both:
fields: %w[credit_card creditCard]
```

## Related Pages

- [Configuration](Configuration) - Full configuration guide
- [Execution Tracking](Execution-Tracking) - What gets logged
- [Production Deployment](Production-Deployment) - Security best practices

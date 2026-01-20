# Attachments

Send images, PDFs, and other files to vision-capable models using the `with:` option.

## Basic Usage

### Single File

```ruby
module LLM
  class VisionAgent < ApplicationAgent
    model "gpt-4o"  # Vision-capable model
    param :question, required: true

    def user_prompt
      question
    end
  end
end

# Local file
LLM::VisionAgent.call(question: "Describe this image", with: "photo.jpg")

# URL
LLM::VisionAgent.call(
  question: "What architecture is shown?",
  with: "https://example.com/building.jpg"
)
```

### Multiple Files

```ruby
LLM::VisionAgent.call(
  question: "Compare these screenshots",
  with: ["screenshot_v1.png", "screenshot_v2.png"]
)
```

## Supported File Types

RubyLLM automatically detects file types:

| Category | Extensions |
|----------|------------|
| **Images** | `.jpg`, `.jpeg`, `.png`, `.gif`, `.webp`, `.bmp` |
| **Videos** | `.mp4`, `.mov`, `.avi`, `.webm` |
| **Audio** | `.mp3`, `.wav`, `.m4a`, `.ogg`, `.flac` |
| **Documents** | `.pdf`, `.txt`, `.md`, `.csv`, `.json`, `.xml` |
| **Code** | `.rb`, `.py`, `.js`, `.ts`, `.html`, `.css`, and more |

## Vision-Capable Models

Not all models support vision. Use these:

| Provider | Models |
|----------|--------|
| **OpenAI** | `gpt-4o`, `gpt-4o-mini`, `gpt-4-turbo` |
| **Anthropic** | `claude-3-5-sonnet`, `claude-3-opus`, `claude-3-haiku` |
| **Google** | `gemini-2.0-flash`, `gemini-1.5-pro` |

## Image Analysis Examples

### Describe an Image

```ruby
module LLM
  class ImageDescriber < ApplicationAgent
    model "gpt-4o"
    param :detail_level, default: "medium"

    def user_prompt
      "Describe this image in #{detail_level} detail."
    end
  end
end

result = LLM::ImageDescriber.call(
  detail_level: "high",
  with: "product_photo.jpg"
)
```

### Extract Text (OCR)

```ruby
module LLM
  class OCRAgent < ApplicationAgent
    model "gpt-4o"

    def user_prompt
      <<~PROMPT
        Extract all text from this image.
        Preserve the original formatting and structure.
        Return the text exactly as it appears.
      PROMPT
    end

    def schema
      @schema ||= RubyLLM::Schema.create do
        string :extracted_text, description: "All text found in image"
        array :text_blocks, of: :object do
          string :content
          string :location, description: "top/middle/bottom"
        end
      end
    end
  end
end

result = LLM::OCRAgent.call(with: "document_scan.png")
puts result[:extracted_text]
```

### Compare Images

```ruby
module LLM
  class ImageComparator < ApplicationAgent
    model "claude-3-5-sonnet"

    def user_prompt
      <<~PROMPT
        Compare these two images and identify:
        1. Similarities
        2. Differences
        3. Which appears higher quality
      PROMPT
    end

    def schema
      @schema ||= RubyLLM::Schema.create do
        array :similarities, of: :string
        array :differences, of: :string
        string :quality_winner, enum: ["first", "second", "equal"]
        string :explanation
      end
    end
  end
end

result = LLM::ImageComparator.call(with: ["design_v1.png", "design_v2.png"])
```

## Document Analysis

### PDF Analysis

```ruby
module LLM
  class PDFAnalyzer < ApplicationAgent
    model "gpt-4o"
    param :focus_area, default: "summary"

    def user_prompt
      <<~PROMPT
        Analyze this PDF document. Focus on: #{focus_area}

        Provide:
        - Main topics covered
        - Key points
        - Any important figures or data
      PROMPT
    end
  end
end

result = LLM::PDFAnalyzer.call(
  focus_area: "financial data",
  with: "annual_report.pdf"
)
```

### Invoice Processing

```ruby
module LLM
  class InvoiceExtractor < ApplicationAgent
    model "gpt-4o"

    def user_prompt
      "Extract invoice details from this document."
    end

    def schema
      @schema ||= RubyLLM::Schema.create do
        string :invoice_number
        string :date
        string :vendor_name
        number :total_amount
        string :currency, default: "USD"
        array :line_items, of: :object do
          string :description
          integer :quantity
          number :unit_price
          number :total
        end
      end
    end
  end
end

result = LLM::InvoiceExtractor.call(with: "invoice.pdf")
# => { invoice_number: "INV-2024-001", total_amount: 1250.00, ... }
```

## URLs vs Local Files

### Local Files

```ruby
# Relative path (from Rails root)
result = LLM::VisionAgent.call(with: "storage/images/photo.jpg")

# Absolute path
result = LLM::VisionAgent.call(with: "/path/to/photo.jpg")

# Active Storage
result = LLM::VisionAgent.call(with: user.avatar.blob.path)
```

### URLs

```ruby
# Direct image URL
result = LLM::VisionAgent.call(with: "https://example.com/image.jpg")

# S3 signed URL
url = document.file.url(expires_in: 1.hour)
result = LLM::VisionAgent.call(with: url)
```

## Debug Mode

```ruby
result = LLM::VisionAgent.call(
  question: "test",
  with: ["image1.png", "image2.png"],
  dry_run: true
)

# => {
#   dry_run: true,
#   agent: "LLM::VisionAgent",
#   attachments: ["image1.png", "image2.png"],
#   ...
# }
```

## Error Handling

```ruby
begin
  result = LLM::VisionAgent.call(
    question: "Describe this",
    with: "missing_file.jpg"
  )
rescue Errno::ENOENT
  # File not found
  Rails.logger.error("Attachment file not found")
rescue => e
  # Other errors (network, invalid format, etc.)
  Rails.logger.error("Attachment error: #{e.message}")
end
```

## Best Practices

### Optimize Image Size

Large images increase cost and latency:

```ruby
# Resize before sending
image = MiniMagick::Image.open("large_photo.jpg")
image.resize "1024x1024>"
image.write "optimized_photo.jpg"

result = LLM::VisionAgent.call(with: "optimized_photo.jpg")
```

### Use Appropriate Detail Level

Some providers support detail levels:

```ruby
# OpenAI specific - in your prompt
def user_prompt
  "Using high detail analysis, describe every element in this image."
end
```

### Batch Related Images

Group related images in a single call:

```ruby
# One call with multiple images (cheaper than multiple calls)
result = LLM::CompareAgent.call(
  with: ["before.jpg", "after.jpg"]
)
```

### Handle Large Documents

For large PDFs, consider chunking:

```ruby
module LLM
  class LargeDocumentAgent < ApplicationAgent
    model "gpt-4o"
    timeout 180  # Longer timeout for large docs

    def user_prompt
      "Analyze this document page by page. Focus on key information."
    end
  end
end
```

## Related Pages

- [Agent DSL](Agent-DSL) - Configuration options
- [Streaming](Streaming) - Stream responses for large analyses
- [Examples](Examples) - More vision examples

# frozen_string_literal: true

# ApplicationImageAnalyzer - Base class for all image analyzers in this application
#
# All image analyzers inherit from this class. Configure shared settings here
# that apply to all analyzers, or override them per-analyzer as needed.
#
# ============================================================================
# IMAGE ANALYZER DSL REFERENCE
# ============================================================================
#
# MODEL CONFIGURATION:
# --------------------
#   model "gpt-4o"                 # Vision model to use
#   analysis_type :detailed        # Type of analysis (see below)
#   version "1.0"                  # Analyzer version (affects cache keys)
#   description "..."              # Human-readable analyzer description
#
# ANALYSIS TYPES:
# ---------------
#   analysis_type :caption         # Short caption only
#   analysis_type :detailed        # Caption + detailed description
#   analysis_type :tags            # Tags/keywords only
#   analysis_type :objects         # Object detection with confidence
#   analysis_type :colors          # Color palette extraction
#   analysis_type :all             # All analysis types combined
#
# ANALYSIS OPTIONS:
# -----------------
#   extract_colors true            # Extract dominant colors
#   detect_objects true            # Detect objects in image
#   extract_text true              # OCR text extraction
#   max_tags 20                    # Maximum number of tags to extract
#
# CUSTOM PROMPTS:
# ---------------
#   custom_prompt "Describe this product for e-commerce..."
#
# CACHING:
# --------
#   cache_for 7.days               # Enable caching with TTL
#
# ============================================================================
# AVAILABLE MODELS
# ============================================================================
#
# OpenAI:
#   - gpt-4o            # Best quality, multimodal
#   - gpt-4o-mini       # Faster, lower cost
#   - gpt-4-vision      # Vision specialist
#
# Anthropic:
#   - claude-3-opus     # Highest quality
#   - claude-3-sonnet   # Balanced
#
# Google:
#   - gemini-pro-vision # Google's vision model
#
# ============================================================================
# USAGE EXAMPLES
# ============================================================================
#
#   # Basic analysis
#   result = Images::MyAnalyzer.call(image: "photo.jpg")
#   result.caption        # => "A sunset over mountains"
#   result.tags           # => ["sunset", "mountains", "nature"]
#
#   # Analyze from URL
#   result = Images::MyAnalyzer.call(image: "https://example.com/image.jpg")
#
#   # Check for specific content
#   result.has_tag?("car")        # => true/false
#   result.has_object?("person")  # => true/false
#
#   # Get color information
#   result.dominant_color         # => { hex: "#FF0000", percentage: 30 }
#
#   # With tenant for budget tracking
#   result = Images::MyAnalyzer.call(image: "photo.jpg", tenant: organization)
#
# ============================================================================
# OTHER IMAGE ANALYZER EXAMPLES
# ============================================================================
#
# See these files for specialized analyzer implementations:
#   - product_analyzer.rb          - E-commerce product analysis
#   - content_analyzer.rb          - Content moderation analysis
#   - scene_analyzer.rb            - Scene understanding
#
module Images
  class ApplicationImageAnalyzer < RubyLLM::Agents::ImageAnalyzer
    # ============================================
    # Shared Model Configuration
    # ============================================
    # These settings are inherited by all image analyzers

    model 'gpt-4o'
    analysis_type :detailed

    # ============================================
    # Shared Analysis Options
    # ============================================

    max_tags 10

    # ============================================
    # Shared Caching
    # ============================================

    # cache_for 1.day  # Enable caching for all analyzers

    # ============================================
    # Shared Helper Methods
    # ============================================
    # Define methods here that can be used by all analyzers
  end
end

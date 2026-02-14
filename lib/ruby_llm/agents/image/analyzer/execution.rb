# frozen_string_literal: true

require "digest"
require "json"
require_relative "../concerns/image_operation_execution"

module RubyLLM
  module Agents
    class ImageAnalyzer
      # Execution logic for image analyzers
      #
      # Handles image validation, budget tracking, caching,
      # analysis execution, and result building.
      #
      module Execution
        include Concerns::ImageOperationExecution

        # Execute the image analysis pipeline
        #
        # @return [ImageAnalysisResult] The result containing analysis data
        def execute
          started_at = Time.current

          resolve_tenant_context!
          check_budget! if budget_tracking_enabled?
          validate_image!

          # Check cache
          cached = check_cache(ImageAnalysisResult) if cache_enabled?
          return cached if cached

          # Analyze image
          analysis_data = analyze_image

          # Build result
          result = build_result(
            analysis: analysis_data,
            started_at: started_at,
            completed_at: Time.current
          )

          # Cache result
          write_cache(result) if cache_enabled?

          # Track execution
          record_execution(result) if execution_tracking_enabled?

          result
        rescue StandardError => e
          record_failed_execution(e, started_at) if execution_tracking_enabled?
          build_error_result(e, started_at)
        end

        private

        def execution_type
          "image_analysis"
        end

        def validate_image!
          raise ArgumentError, "Image cannot be blank" if image.nil?

          # Validate image exists if it's a path
          if image.is_a?(String) && !image.start_with?("http")
            unless File.exist?(image)
              raise ArgumentError, "Image file does not exist: #{image}"
            end
          end
        end

        def analyze_image
          # Build the analysis prompt based on configuration
          prompt = build_analysis_prompt

          # Use RubyLLM's vision capabilities
          response = call_vision_model(prompt)

          # Parse the response into structured data
          parse_analysis_response(response)
        end

        def build_analysis_prompt
          return resolve_custom_prompt if resolve_custom_prompt

          parts = []
          analysis = resolve_analysis_type

          case analysis
          when :caption
            parts << "Provide a brief, single-sentence caption for this image."
          when :detailed
            parts << "Provide a detailed description of this image including:"
            parts << "- A brief caption (1 sentence)"
            parts << "- A detailed description (2-3 paragraphs)"
            parts << "- Key tags/keywords (up to #{resolve_max_tags})"
          when :tags
            parts << "List up to #{resolve_max_tags} relevant tags/keywords for this image as a comma-separated list."
          when :objects
            parts << "Identify all objects visible in this image. For each object provide:"
            parts << "- Name of the object"
            parts << "- Approximate location (top-left, center, bottom-right, etc.)"
            parts << "- Confidence level (high, medium, low)"
          when :colors
            parts << "Identify the dominant colors in this image. For each color provide:"
            parts << "- Hex color code"
            parts << "- Color name"
            parts << "- Approximate percentage of the image"
          when :all
            parts << "Analyze this image comprehensively. Provide:"
            parts << "1. A brief caption (1 sentence)"
            parts << "2. A detailed description (2-3 paragraphs)"
            parts << "3. Key tags/keywords (up to #{resolve_max_tags})"
            parts << "4. Objects detected with locations"
            parts << "5. Dominant colors with hex codes and percentages"
          end

          # Add conditional extraction requests
          if resolve_extract_colors && analysis != :colors && analysis != :all
            parts << "\nAlso identify the dominant colors (hex, name, percentage)."
          end

          if resolve_detect_objects && analysis != :objects && analysis != :all
            parts << "\nAlso identify objects visible with their locations."
          end

          if resolve_extract_text
            parts << "\nAlso extract any visible text (OCR)."
          end

          parts << "\nFormat your response as JSON with the following structure:"
          parts << build_json_schema

          parts.join("\n")
        end

        def build_json_schema
          schema = {
            caption: "Brief caption string",
            description: "Detailed description string (if applicable)",
            tags: ["array", "of", "tag", "strings"],
            objects: [{ name: "object name", location: "position", confidence: "high/medium/low" }],
            colors: [{ hex: "#RRGGBB", name: "color name", percentage: 25 }],
            text: "Extracted text if any"
          }

          JSON.pretty_generate(schema)
        end

        def call_vision_model(prompt)
          model = resolve_model

          # Prepare image for the vision model
          image_content = prepare_image_content

          # Use RubyLLM chat with vision
          chat = RubyLLM.chat(model: model)
          chat.ask(prompt, with: { image: image_content })
        end

        def prepare_image_content
          if image.is_a?(String)
            if image.start_with?("http")
              # URL - pass directly
              image
            else
              # File path - read and encode as base64
              require "base64"
              mime_type = detect_mime_type(image)
              data = Base64.strict_encode64(File.binread(image))
              "data:#{mime_type};base64,#{data}"
            end
          elsif image.respond_to?(:read)
            # IO object - read and encode
            require "base64"
            content = image.read
            image.rewind if image.respond_to?(:rewind)
            data = Base64.strict_encode64(content)
            "data:image/png;base64,#{data}"
          else
            image.to_s
          end
        end

        def detect_mime_type(path)
          ext = File.extname(path).downcase
          case ext
          when ".jpg", ".jpeg" then "image/jpeg"
          when ".png" then "image/png"
          when ".gif" then "image/gif"
          when ".webp" then "image/webp"
          when ".bmp" then "image/bmp"
          else "image/png"
          end
        end

        def parse_analysis_response(response)
          content = response.content

          # Try to extract JSON from the response
          json_match = content.match(/\{[\s\S]*\}/m)
          if json_match
            begin
              parsed = JSON.parse(json_match[0], symbolize_names: true)
              normalize_analysis_data(parsed)
            rescue JSON::ParserError
              # Fall back to text parsing
              parse_text_response(content)
            end
          else
            parse_text_response(content)
          end
        end

        def normalize_analysis_data(data)
          {
            caption: data[:caption]&.to_s,
            description: data[:description]&.to_s,
            tags: normalize_tags(data[:tags]),
            objects: normalize_objects(data[:objects]),
            colors: normalize_colors(data[:colors]),
            text: data[:text]&.to_s,
            raw_response: data
          }
        end

        def normalize_tags(tags)
          return [] unless tags.is_a?(Array)

          tags.map(&:to_s).map(&:strip).reject(&:empty?).first(resolve_max_tags)
        end

        def normalize_objects(objects)
          return [] unless objects.is_a?(Array)

          objects.map do |obj|
            next unless obj.is_a?(Hash)
            {
              name: obj[:name]&.to_s,
              location: obj[:location]&.to_s,
              confidence: obj[:confidence]&.to_s&.downcase,
              bbox: obj[:bbox] || obj[:bounding_box]
            }.compact
          end.compact
        end

        def normalize_colors(colors)
          return [] unless colors.is_a?(Array)

          colors.map do |color|
            next unless color.is_a?(Hash)
            {
              hex: color[:hex]&.to_s,
              name: color[:name]&.to_s,
              percentage: color[:percentage]&.to_f
            }.compact
          end.compact
        end

        def parse_text_response(content)
          # Basic text parsing when JSON extraction fails
          {
            caption: extract_caption_from_text(content),
            description: content,
            tags: extract_tags_from_text(content),
            objects: [],
            colors: [],
            text: nil,
            raw_response: content
          }
        end

        def extract_caption_from_text(content)
          # Try to extract first sentence as caption
          first_sentence = content.split(/[.!?]/).first&.strip
          first_sentence&.slice(0, 200)
        end

        def extract_tags_from_text(content)
          # Extract potential tags from comma-separated lists or bullet points
          tags = []

          # Look for bullet point lists
          content.scan(/[-*•]\s*(\w+(?:\s+\w+)?)/).each do |match|
            tags << match[0].strip.downcase
          end

          # Look for comma-separated items after "tags:" or "keywords:"
          if content =~ /(?:tags|keywords)[:\s]*(.+?)(?:\n|$)/i
            Regexp.last_match(1).split(/[,;]/).each do |tag|
              tags << tag.strip.downcase
            end
          end

          tags.uniq.first(resolve_max_tags)
        end

        def build_result(analysis:, started_at:, completed_at:)
          ImageAnalysisResult.new(
            image: image,
            model_id: resolve_model,
            analysis_type: resolve_analysis_type,
            caption: analysis[:caption],
            description: analysis[:description],
            tags: analysis[:tags],
            objects: analysis[:objects],
            colors: analysis[:colors],
            text: analysis[:text],
            raw_response: analysis[:raw_response],
            started_at: started_at,
            completed_at: completed_at,
            tenant_id: @tenant_id,
            analyzer_class: self.class.name
          )
        end

        def build_error_result(error, started_at)
          ImageAnalysisResult.new(
            image: image,
            model_id: resolve_model,
            analysis_type: resolve_analysis_type,
            caption: nil,
            description: nil,
            tags: [],
            objects: [],
            colors: [],
            text: nil,
            raw_response: nil,
            started_at: started_at,
            completed_at: Time.current,
            tenant_id: @tenant_id,
            analyzer_class: self.class.name,
            error_class: error.class.name,
            error_message: error.message
          )
        end

        # Resolution methods

        def resolve_analysis_type
          options[:analysis_type] || self.class.analysis_type
        end

        def resolve_extract_colors
          options.fetch(:extract_colors, self.class.extract_colors)
        end

        def resolve_detect_objects
          options.fetch(:detect_objects, self.class.detect_objects)
        end

        def resolve_extract_text
          options.fetch(:extract_text, self.class.extract_text)
        end

        def resolve_custom_prompt
          options[:custom_prompt] || self.class.custom_prompt
        end

        def resolve_max_tags
          options[:max_tags] || self.class.max_tags
        end

        # Cache key components
        def cache_key_components
          [
            "image_analyzer",
            self.class.name,
            resolve_model,
            resolve_analysis_type.to_s,
            resolve_extract_colors.to_s,
            resolve_detect_objects.to_s,
            resolve_extract_text.to_s,
            Digest::SHA256.hexdigest(image_digest)
          ]
        end

        def image_digest
          if image.is_a?(String) && File.exist?(image)
            File.read(image)
          elsif image.respond_to?(:read)
            content = image.read
            image.rewind if image.respond_to?(:rewind)
            content
          else
            image.to_s
          end
        end

        def build_metadata(result)
          {
            analysis_type: result.analysis_type,
            tags_count: result.tags.size,
            objects_count: result.objects.size,
            colors_count: result.colors.size,
            has_text: result.text.present?
          }
        end
      end
    end
  end
end

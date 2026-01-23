# frozen_string_literal: true

# ChildSafeModerator - Very strict moderation for children's content
#
# A standalone moderator with extremely low thresholds designed for
# applications targeting children or requiring maximum safety.
#
# Use cases:
# - Educational apps for children
# - Family-friendly content platforms
# - Content that must meet COPPA compliance
# - Any application requiring maximum safety
#
# Related examples:
# - content_moderator.rb   - Standard moderation
# - forum_moderator.rb     - Balanced community moderation
#
# @example In a controller
#   def create
#     result = Llm::Text::ChildSafeModerator.call(text: params[:content])
#     if result.flagged?
#       render json: { error: "Content not appropriate for children" },
#              status: :unprocessable_entity
#       return
#     end
#     @content = Content.create!(body: params[:content])
#     render json: @content
#   end
#
# @example Batch moderation
#   comments = Comment.pending_review
#   comments.each do |comment|
#     result = Llm::Text::ChildSafeModerator.call(text: comment.body)
#     if result.flagged?
#       comment.update!(status: :rejected, rejection_reason: result.flagged_categories.join(', '))
#     else
#       comment.update!(status: :approved)
#     end
#   end
#
# @example Checking specific categories
#   result = Llm::Text::ChildSafeModerator.call(text: content)
#   if result.flagged?
#     puts "Flagged categories: #{result.flagged_categories}"
#     puts "Category scores:"
#     result.category_scores.each do |category, score|
#       puts "  #{category}: #{score.round(4)}"
#     end
#   end
#
module Llm
  module Text
    class ChildSafeModerator < RubyLLM::Agents::Moderator
      description "Very strict moderation for children's content"
      version "1.0"

      # Use latest moderation model
      model "omni-moderation-latest"

      # Very low threshold - flag anything remotely concerning
      # 0.3 means content is flagged if any category scores above 30%
      threshold 0.3

      # Check all child-relevant categories
      # Especially strict about sexual content and violence
      categories :sexual,
                 :violence,
                 :self_harm,
                 :hate,
                 :harassment
    end
  end
end

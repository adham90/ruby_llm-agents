# frozen_string_literal: true

# ForumModerator - Balanced moderation for community forums
#
# A standalone moderator with balanced thresholds designed for
# community-generated content. Allows reasonable discussion while
# blocking clearly harmful content.
#
# Use cases:
# - Discussion forums
# - Comment sections
# - User reviews
# - Community posts
#
# Related examples:
# - content_moderator.rb     - Standard moderation
# - child_safe_moderator.rb  - Very strict moderation
#
# @example In a Rails controller
#   class PostsController < ApplicationController
#     def create
#       result = Moderators::ForumModerator.call(text: params[:body])
#
#       if result.flagged?
#         @post = Post.create!(
#           body: params[:body],
#           status: :pending_review,
#           moderation_flags: result.flagged_categories
#         )
#         render json: @post.merge(notice: "Post submitted for review")
#       else
#         @post = Post.create!(body: params[:body], status: :published)
#         render json: @post
#       end
#     end
#   end
#
# @example In a background job
#   class ModeratePostJob < ApplicationJob
#     queue_as :moderation
#
#     def perform(post_id)
#       post = Post.find(post_id)
#       result = Moderators::ForumModerator.call(text: post.body)
#
#       if result.flagged?
#         post.update!(
#           status: :flagged,
#           moderation_result: {
#             categories: result.flagged_categories,
#             scores: result.category_scores,
#             reviewed_at: Time.current
#           }
#         )
#         # Notify moderators
#         ModeratorMailer.flagged_post(post).deliver_later
#       else
#         post.update!(status: :published)
#       end
#     end
#   end
#
# @example With runtime override
#   # Use stricter threshold for first-time posters
#   result = Moderators::ForumModerator.call(
#     text: post.body,
#     threshold: user.posts_count.zero? ? 0.5 : 0.8
#   )
#
module Moderators
  class ForumModerator < RubyLLM::Agents::Moderator
    description "Balanced moderation for community forums"
    version "1.0"

    # Use latest moderation model
    model "omni-moderation-latest"

    # Balanced threshold - allow discussion, block clear violations
    # 0.8 means content is flagged only if a category scores above 80%
    threshold 0.8

    # Focus on categories most relevant to forum discussions
    # These are the most common policy violations in community content
    categories :hate,
               :harassment
  end
end

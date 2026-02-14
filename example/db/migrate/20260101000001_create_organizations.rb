# frozen_string_literal: true

class CreateOrganizations < ActiveRecord::Migration[8.1]
  def change
    create_table :organizations do |t|
      t.string :slug, null: false, index: { unique: true }
      t.string :name, null: false
      t.string :plan, default: "free"

      # Encrypted API keys (use Rails 7+ encryption in model)
      t.string :openai_api_key
      t.string :anthropic_api_key
      t.string :gemini_api_key

      # Organization metadata
      t.string :industry
      t.integer :employee_count
      t.boolean :active, default: true

      t.timestamps
    end

    add_index :organizations, :plan
    add_index :organizations, :active
  end
end

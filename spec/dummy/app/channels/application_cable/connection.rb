# frozen_string_literal: true

module ApplicationCable
  class Connection < ActionCable::Connection::Base
    # For development/testing, allow all connections
    # In production, you would add authentication here
    def connect
      logger.info "[ActionCable] Connection established"
    end

    def disconnect
      logger.info "[ActionCable] Connection closed"
    end
  end
end

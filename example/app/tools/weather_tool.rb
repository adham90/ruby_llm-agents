# frozen_string_literal: true

# Sample weather lookup tool for demonstrating tools DSL
#
# This tool shows how to:
# - Return mock data (for demo purposes)
# - Format multi-line output
# - Use boolean parameters
#
# @example Usage via ToolsAgent
#   ToolsAgent.call(query: "What's the weather in Tokyo?")
#
class WeatherTool < RubyLLM::Tool
    description "Get current weather for a location. Returns temperature, conditions, humidity, and optionally a forecast."

    param :location, desc: "City name or location", required: true
    param :units, desc: "Temperature units: celsius or fahrenheit (default: celsius)", required: false
    param :include_forecast, desc: "Include 3-day forecast (default: false)", type: :boolean, required: false

    # Mock weather data for demonstration
    MOCK_DATA = {
      "tokyo" => { temp_c: 22, conditions: "Partly Cloudy", humidity: 65, wind: "10 km/h NE" },
      "new york" => { temp_c: 18, conditions: "Sunny", humidity: 55, wind: "15 km/h W" },
      "london" => { temp_c: 14, conditions: "Rainy", humidity: 80, wind: "20 km/h SW" },
      "paris" => { temp_c: 16, conditions: "Cloudy", humidity: 70, wind: "12 km/h N" },
      "sydney" => { temp_c: 25, conditions: "Sunny", humidity: 60, wind: "8 km/h SE" }
    }.freeze

    def execute(location:, units: nil, include_forecast: nil)
      units ||= "celsius"
      include_forecast = false if include_forecast.nil?
      normalized_location = location.to_s.downcase.strip
      weather = MOCK_DATA[normalized_location]

      unless weather
        return "Weather data not available for '#{location}'. Try: Tokyo, New York, London, Paris, or Sydney."
      end

      temp = format_temperature(weather[:temp_c], units)

      output = <<~WEATHER
        Weather for #{location.titleize}:
        Temperature: #{temp}
        Conditions: #{weather[:conditions]}
        Humidity: #{weather[:humidity]}%
        Wind: #{weather[:wind]}
      WEATHER

      if include_forecast
        output += <<~FORECAST

          3-Day Forecast:
          - Tomorrow: #{weather[:conditions]}, #{format_temperature(weather[:temp_c] + rand(-3..3), units)}
          - Day 2: #{%w[Sunny Cloudy Rainy].sample}, #{format_temperature(weather[:temp_c] + rand(-5..5), units)}
          - Day 3: #{%w[Sunny Partly\ Cloudy Clear].sample}, #{format_temperature(weather[:temp_c] + rand(-4..4), units)}
        FORECAST
      end

      output
    end

    private

    def format_temperature(temp_c, units)
      if units.to_s.downcase.start_with?("f")
        temp_f = (temp_c * 9.0 / 5.0) + 32
        "#{temp_f.round(1)}F"
      else
        "#{temp_c}C"
      end
    end
end

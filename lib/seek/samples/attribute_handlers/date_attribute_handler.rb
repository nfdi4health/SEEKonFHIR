module Seek
  module Samples
    module AttributeHandlers
      class DateAttributeHandler < BaseAttributeHandler
        def test_value(value)
          raise 'Not a date time' unless Date.parse(value.to_s)
        end
      end
    end
  end
end

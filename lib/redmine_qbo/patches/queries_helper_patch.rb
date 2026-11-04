#The MIT License (MIT)
#
#Copyright (c) 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

module RedmineQbo
  module Patches
    # Links the Customer column in issue lists to the customer's page, for users who may open it
    # (View customers). Others see the name as plain text. CSV and PDF exports are unchanged.
    module QueriesHelperPatch
      def column_value(column, item, value)
        return super unless column.name == :customer && value.is_a?(Customer) && qbo_can_view_customers?

        link_to(value.to_s, customer_path(value))
      end

      private

      def qbo_can_view_customers?
        return @qbo_can_view_customers if defined?(@qbo_can_view_customers)

        @qbo_can_view_customers = User.current.allowed_to?(:view_customers, nil, global: true)
      end
    end
  end
end

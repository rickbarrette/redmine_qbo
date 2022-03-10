#The MIT License (MIT)
#
#Copyright (c) 2022 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

require_dependency 'time_entry_query'

module TimeEntryQueryPatch

  # Add QBO options to columns
  def available_columns
    unless @available_columns
      @available_columns = self.class.available_columns.dup
      @available_columns << QueryColumn.new(:billed, :sortable => "#{TimeEntry.table_name}.name", :groupable => true, :caption => :field_billed)
    end
    super
  end
  
  # Add QBO options to the filter
  def initialize_available_filters
    add_available_filter "billed", :type => :boolean
    super
  end

end

# Add module to TimeEntryQuery
TimeEntryQuery.send(:prepend, QueryPatch)

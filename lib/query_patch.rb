#The MIT License (MIT)
#
#Copyright (c) 2017 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

require_dependency 'issue_query'

module QueryPatch

  def self.included(base) # :nodoc:
    base.extend(ClassMethods)

    base.send(:include, InstanceMethods)

    # Same as typing in the class 
    base.class_eval do
      unloadable # Send unloadable so it will not be unloaded in development
      
      alias_method_chain :available_columns, :qbo
      alias_method_chain :available_filters, :qbo
    end
  end
      
  module ClassMethods
    
  end
  
  module InstanceMethods
  
    def available_columns_with_qbo
      unless @available_columns
        @available_columns = available_columns_without_qbo
        @available_columns << QueryColumn.new(:customer, :sortable => "#{Customer.table_name}.name", :groupable => true, :caption => :field_customer)
        @available_columns << QueryColumn.new(:qbo_billed, :sortable => "#{TimeEntry.table_name}.qbo_billed", :groupable => true, :caption => :field_qbo_billed)
      end
      @available_columns
    end
    
    def available_filters_with_qbo
      unless @available_filters
        @available_filters = available_filters_without_qbo 
        
        #qbo_filters = {
        #  :customer => { 
        #    :id => l(:field_customer),
        #    :type => :integer, 
        #    :order => @available_filters.size + 1},
        #}
        
        #qbo_filters = { 
        #  "customer_id" => {
        #    :id => :customer_id,
        #    :type => :list_optional
            #:order => @available_filters.size + 1,
            #:values => Customer.find(:all).collect { |c| [c.name, c.id.to_s]}
        #  }
        #}
        
        #@available_filters.merge!(qbo_filters)
      end
      @available_filters
    end
  end
end

# Add module to Issue
IssueQuery.send(:include, QueryPatch)

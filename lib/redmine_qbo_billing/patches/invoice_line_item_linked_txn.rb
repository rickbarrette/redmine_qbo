#The MIT License (MIT)
#
#Copyright (c) 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

module RedmineQboBilling
  module Patches
    # quickbooks-ruby's invoice lines have no LinkedTxn, which QuickBooks needs on each line that bills a
    # time activity ("When linking a TimeActivity to an Invoice you must also link it to a sales line item").
    # This adds it, placed right after Amount where QuickBooks' schema has it.
    module InvoiceLineItemLinkedTxn
      module_function

      def apply!
        klass = Quickbooks::Model::InvoiceLineItem
        return if klass.method_defined?(:linked_transactions)

        klass.class_eval do
          xml_accessor :linked_transactions, from: 'LinkedTxn', as: [Quickbooks::Model::LinkedTransaction]
        end

        # Move the new element from the end to after Amount, so it's written in schema order
        attrs = klass.instance_variable_get(:@roxml_attrs)
        return unless attrs.is_a?(Array)

        linked = attrs.detect { |a| a.respond_to?(:accessor) && a.accessor == 'linked_transactions' }
        amount_index = attrs.index { |a| a.respond_to?(:accessor) && a.accessor == 'amount' }
        return unless linked && amount_index

        attrs.delete(linked)
        attrs.insert(amount_index + 1, linked)
      end
    end
  end
end

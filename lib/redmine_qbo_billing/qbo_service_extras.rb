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
  # What the plugin's estimate and invoice services add to quickbooks-ruby's: QuickBooks' newer custom
  # fields on every request, emailing the document, and an authenticated service for a block.
  module QboServiceExtras
    # QuickBooks only includes its newer custom fields (the ones made under Settings > Custom fields, which
    # aren't listed in the company preferences) when asked for them, on minor version 70 or later
    MINOR_VERSION = 75
    ENHANCED_CUSTOM_FIELDS = 'enhancedAllCustomFields'.freeze

    def self.included(base)
      base.extend(ClassMethods)
    end

    module ClassMethods
      # Runs the block with an authenticated service, refreshing the QuickBooks token when needed
      def with_service
        qbo = QboConnectionService.current!
        qbo.perform_authenticated_request do |access_token|
          yield new(company_id: qbo.realm_id, access_token: access_token)
        end
      end
    end

    # Emails the document to the customer (to email_address, or the document's billing email when blank).
    # QuickBooks uses its own email template, marks the document as sent and returns it.
    def send_document(id, email_address = nil)
      query = email_address.present? ? "?sendTo=#{CGI.escape(email_address.to_s.strip)}" : ""
      url = "#{url_for_resource(model::REST_RESOURCE)}/#{id}/send#{query}"
      response = do_http_post(url, "", {}, { 'Content-Type' => 'application/octet-stream' })
      return nil unless response.code.to_i == 200

      model.from_xml(parse_singular_entity_response(model, response.plain_body))
    end

    private

    # Every request from these services (reads, queries, saves, emails) asks for all custom fields. Only
    # these services do, so redmine_qbo's own calls are unchanged.
    def add_query_string_to_url(url, params = {})
      params = params.is_a?(Hash) ? params.dup : {}
      params['minorversion'] = [Quickbooks.minorversion.to_i, MINOR_VERSION].max
      params['include'] = ENHANCED_CUSTOM_FIELDS
      delimiter = url.include?('?') ? '&' : '?'
      url + delimiter + params.map { |key, value| "#{key}=#{value}" }.join('&')
    end
  end
end

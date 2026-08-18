#The MIT License (MIT)
#
#Copyright (c) 2016 - 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

module RedmineQbo
  module Patches
    module AttachmentsControllerPatch
      def self.apply
        AttachmentsController.class_eval do
          # 1. PREPEND: Must run before ANY of Redmine's ApplicationController filters
          prepend_before_action :set_customer_token_thread

          # 2. Skip global login redirects if the user holds a valid token for this file
          skip_before_action :check_if_login_required, if: :valid_customer_token?
          skip_before_action :check_project_privacy, raise: false, if: :valid_customer_token?

          # Note: We do NOT need to skip :read_authorize anymore. 
          # Because we patched Attachment#visible?, read_authorize will pass naturally!

          private

          def set_customer_token_thread
            if session[:token].present?
              Thread.current[:customer_token] = CustomerToken.active.find_by(token: session[:token])
            end
          end

          def valid_customer_token?
            token = Thread.current[:customer_token]
            return false unless token

            # Handle "Download All" zip requests (object_type=issues, object_id=ID)
            if params[:action] == 'download_all'
              return params[:object_type] == 'issues' && params[:object_id].to_i == token.issue_id
            end

            # Handle normal single attachment requests (show, download, thumbnail)
            attachment = Attachment.find_by(id: params[:id])
            return false unless attachment

            # Allow if attachment belongs directly to the Issue
            if attachment.container_type == 'Issue' && attachment.container_id == token.issue_id
              return true
            end
            
            # Allow if attachment belongs to a Journal (comment) on the Issue
            if attachment.container_type == 'Journal' && attachment.container.journalized_type == 'Issue' && attachment.container.journalized_id == token.issue_id
              return true
            end
            
            false
          end
        end
      end
    end
  end
end
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
      # Redmine's own access checks, which deny the anonymous viewer of a share link. Each one defers
      # to Redmine unless the session holds a customer share token for the issue the file belongs to.
      module CustomerTokenAccess
        private

        def read_authorize
          valid_customer_token? || super
        end

        def find_container
          return super unless customer_token_for_download_all?

          @container = Issue.find(params[:object_id])
          @project = @container.project
        rescue ActiveRecord::RecordNotFound
          render_404
        end

        def find_downloadable_attachments
          return super unless customer_token_for_download_all?

          @attachments = @container.attachments.select(&:readable?)
          bulk_download_max_size = Setting.bulk_download_max_size.to_i.kilobytes
          if @attachments.sum(&:filesize) > bulk_download_max_size
            flash[:error] = l(:error_bulk_download_size_too_big, max_size: number_to_human_size(bulk_download_max_size.to_i))
            redirect_back_or_default(container_url, referer: true)
          end
        end
      end

      def self.apply
        AttachmentsController.prepend(CustomerTokenAccess)

        AttachmentsController.class_eval do
          # Must run before any of Redmine's ApplicationController filters
          prepend_before_action :load_customer_token

          # Skip the login redirect if the session holds a valid token for this file
          skip_before_action :check_if_login_required, if: :valid_customer_token?

          private

          # Kept on the controller instance (one per request) rather than Thread.current, which is reused
          # across requests by the web server and could carry one customer's token into another request.
          def load_customer_token
            @customer_token = session[:token].present? ? CustomerToken.active.find_by(token: session[:token]) : nil
          end

          def customer_token_for_download_all?
            @customer_token.present? && params[:action] == 'download_all' &&
              params[:object_type] == 'issues' && params[:object_id].to_i == @customer_token.issue_id
          end

          def valid_customer_token?
            token = @customer_token
            return false unless token
            return customer_token_for_download_all? if params[:action] == 'download_all'
            return false unless %w[show download thumbnail].include?(params[:action])

            attachment = Attachment.find_by(id: params[:id])
            return false unless attachment

            case attachment.container_type
            when 'Issue'
              attachment.container_id == token.issue_id
            when 'Journal'
              journal = attachment.container
              journal&.journalized_type == 'Issue' && journal.journalized_id == token.issue_id && !journal.private_notes?
            else
              false
            end
          end
        end
      end
    end
  end
end

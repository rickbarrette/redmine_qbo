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
      module Helper
        # Check if login is globally required to access the application
        def check_if_login_required
          # Return true if the user is already logged in
          return true if User.current.logged?

          # Pull up the attachment and verify if we have a valid token for the issue
          attachment = Attachment.find_by(id: params[:id])
          return require_login if attachment.nil?

          token = CustomerToken.where("token = ? AND expires_at > ?", session[:token], Time.current).first
          return true if token&.issue_id == attachment.container_id

          # Default to requiring login if all else fails
          require_login if Setting.login_required?
        end
      end

      def self.apply
        AttachmentsController.class_eval do
          helper Helper
        end
      end
    end
  end
end
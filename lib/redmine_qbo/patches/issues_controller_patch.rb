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
    module IssuesControllerPatch
      module Helper
        # Extend the watcher links to include billing and share options
        def watcher_link(issue, user)
          links = ''
          
          # Users with the "Bill issues" permission can bill time (POST, so it can't be triggered by a plain link)
          if user.allowed_to?(:bill_issues, issue.project)
            links << link_to(I18n.t(:label_bill_time), bill_path(issue.id), method: :post,
                             data: { confirm: I18n.t(:text_are_you_sure) }, class: 'icon icon-email-add')
          end

          # Users with the "Share issues with customers" permission can create a customer link
          if user.allowed_to?(:share_issues_with_customers, nil, global: true)
            links << link_to(I18n.t(:label_share), share_path(issue.id), method: :get, target: :_blank, class: 'icon icon-shared')
          end

          # Append to the original watcher links
          (links.html_safe + super).html_safe
        end
      end

      def self.apply
        IssuesController.class_eval do
          helper Helper
        end
      end
    end
  end
end
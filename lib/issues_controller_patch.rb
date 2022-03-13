#The MIT License (MIT)
#
#Copyright (c) 2022 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
require_dependency 'issues_controller'

module IssuesControllerPatch

  module Helper
    def watcher_link(issue, user)
      link = +''
      link << link_to(I18n.t(:label_bill_time), bill_path( issue.id ), method: :get, class: 'icon icon-email-add') if user.admin?
      link << link_to(I18n.t(:label_share), share_path( issue.id ), method: :get, target: :_blank, class: 'icon icon-shared') if user.logged?
      link.html_safe + super
    end
  end

  def self.included(base)

    base.class_eval do
      unloadable # Send unloadable so it will not be unloaded in development
      helper Helper
    end

  end

end   

# Add module to IssuessController
IssuesController.send(:include, IssuesControllerPatch)

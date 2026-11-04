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
    # The activity page lists every activity type for the whole site, and a project's page those its members may
    # see. QuickBooks estimates, invoices and payments (QboActivity) belong to no project: they're kept to the
    # overall page, and to users with one of their permissions, so nobody gets a checkbox for activity they can't see.
    module ActivityFetcherPatch
      def event_types
        return @event_types if @qbo_activity_checked

        @qbo_activity_checked = true
        @event_types = super.select do |event_type|
          providers = Redmine::Activity.providers[event_type].map(&:constantize)
          qbo = providers.select { |provider| provider.respond_to?(:qbo_activity_visible_to?) }
          qbo.empty? || (project.nil? && qbo.any? { |provider| provider.qbo_activity_visible_to?(user) })
        end
      end
    end
  end
end

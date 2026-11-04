#The MIT License (MIT)
#
#Copyright (c) 2016 - 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

# Estimates, invoices and payments on Redmine's activity page. They come from QuickBooks and belong to no
# project, so they show on the overall activity page only (not a project's, nor a user's), and each kind only to
# users with one of its global permissions.
module QboActivity
  extend ActiveSupport::Concern

  class_methods do
    # event_type: the activity type registered in init.rb (e.g. 'qbo_estimates'); icon: the event's CSS class
    # and icon in this plugin's sprite (assets/images/icons.svg); permissions: any one of these shows it
    def qbo_activity(event_type, icon:, permissions:, title:, description:, url:)
      # These models can load before Redmine adds acts_as_event to every model
      include Redmine::Acts::Event unless respond_to?(:acts_as_event)
      acts_as_event title: title, description: description, url: url, type: icon,
                    datetime: :activity_datetime, author: nil
      class_attribute :qbo_activity_permissions, instance_writer: false, default: permissions
      class_attribute :qbo_activity_event_type, instance_writer: false, default: event_type
    end

    def qbo_activity_visible_to?(user)
      qbo_activity_permissions.any? { |permission| user.allowed_to?(permission, nil, global: true) }
    end

    # What Redmine::Activity::Fetcher reads for a project's activity page; these never show there
    def activity_provider_options
      { qbo_activity_event_type => { permission: qbo_activity_permissions.first } }
    end

    # Documents dated from..to (the page's days, to not included), newest first. From the QuickBooks date, so
    # a sync bringing in old documents doesn't pile them onto the day it ran.
    def find_events(event_type, user, from, to, options)
      return [] if options[:project] || options[:author] || !qbo_activity_visible_to?(user)

      scope = includes(:customer).where.not(txn_date: nil)
      scope = scope.where('txn_date >= ?', from.to_date) if from
      scope = scope.where('txn_date < ?', to.to_date) if to
      scope = scope.order(txn_date: :desc, id: :desc).limit(options[:limit]) if options[:limit]
      scope.to_a
    end
  end

  # When it happened: the time it reached Redmine when that was its QuickBooks date (created or changed in
  # QuickBooks and sent by the webhook moments later), else midday on its QuickBooks date (e.g. a full sync)
  def activity_datetime
    return created_at if created_at && created_at.getlocal.to_date == txn_date

    Time.local(txn_date.year, txn_date.month, txn_date.day, 12)
  end

  # Activity events have a project; these don't
  def project
    nil
  end

  def activity_money(amount)
    ActiveSupport::NumberHelper.number_to_currency(amount) if amount
  end

  def activity_customer
    customer&.name.presence || I18n.t(:label_none)
  end
end

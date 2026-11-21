#The MIT License (MIT)
#
#Copyright (c) 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

# Emails a customer the summary of their refund (SOP-OPS-014). It goes out like redmine_qbo_reminders' appointment
# reminders when that plugin is installed (its From, Reply-To and SMTP server, e.g. the shop's sales mailbox);
# otherwise through Redmine's own email settings, from Redmine's emission address. Not Redmine's Mailer, which only
# writes to Redmine users and adds Redmine's headers and footer.
class QboRefundMailer < ActionMailer::Base
  layout false
  self.raise_delivery_errors = true

  class DeliveryOff < StandardError; end

  def refund_summary(refund, email)
    @refund = refund
    @customer = refund.customer
    settings = RedmineQboBilling.mail_settings
    @shop_name = settings[:shop_name].presence || Setting.app_title
    delivery = settings[:delivery] || {}
    if delivery.empty? && !ActionMailer::Base.perform_deliveries
      raise DeliveryOff, I18n.t(:text_refund_email_off)
    end

    options = { to: email, from: settings[:from].presence || Setting.mail_from.to_s,
                subject: I18n.t(:text_refund_email_subject, shop: @shop_name, amount: RedmineQboBilling::RefundWriter.money(refund.refund_amount)) }
    options[:reply_to] = settings[:reply_to] if settings[:reply_to]
    message = mail(options.merge(delivery)) do |format|
      format.text
    end
    message.perform_deliveries = true unless delivery.empty?
    message
  end
end

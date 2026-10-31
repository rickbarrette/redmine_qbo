#The MIT License (MIT)
#
#Copyright (c) 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

class AccountsController < ApplicationController
  layout 'admin'
  menu_item :redmine_qbo_items

  # Accounts come from QuickBooks; choosing the default and syncing are admin-only
  before_action :require_admin

  def index
    @accounts = Account.where(classification: 'Revenue').order(:name)
  end

  def set_default
    account = Account.find_by(id: params[:default_account_id])

    if account&.update(default: true)
      flash[:notice] = l(:notice_default_account_updated)
    else
      flash[:error] = l(:error_default_account_not_selected)
    end
    redirect_to accounts_path
  end

  def sync
    Account.sync
    redirect_to :home, flash: { notice: I18n.t(:label_syncing) }
  end
end
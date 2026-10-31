#The MIT License (MIT)
#
#Copyright (c) 2016 - 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

#authentication
get 'qbo/authenticate', to: 'qbo#authenticate'
get 'qbo/oauth_callback', to: 'qbo#oauth_callback'

#manual sync
get 'qbo/sync', to: 'qbo#sync'
get 'invoices/sync', to: 'invoices#sync'
get 'estimates/sync', to: 'estimates#sync'
get 'employees/sync', to: 'employees#sync'

#webhook
post 'qbo/webhook', to: 'qbo#webhook'

# Estimate & Invoice PDF
get 'estimates/:id', to: 'estimates#show', as: :estimate
get 'estimates/doc/', to: 'estimates#doc', as: :estimate_doc
get 'invoices/:id', to: 'invoices#show', as: :invoice

#manual billing
post 'bill/:id', to: 'qbo#bill', as: :bill

#customer issue view
get 'customers/view/:token', to: 'customers#view', as: :view
get 'customers/share/:id', to: 'customers#share', as: :share

#java script routes
get 'filter_estimates_by_customer' => 'customers#filter_estimates_by_customer'
get 'filter_invoices_by_customer' => 'customers#filter_invoices_by_customer'

resources :customers do
  collection do
    get :autocomplete
    get :sync
  end
end

# Estimate writer pages. Kept under /qbo_estimates so they don't clash with redmine_qbo's /estimates/:id PDF route.
resources :qbo_estimates, only: [:new, :create, :edit, :update] do
  member do
    post :send_email
    get :issues_preview
    post :create_issues
  end
  collection do
    get :customer_info
    get :items
    post :refresh_company
  end
end

# Invoice writer pages (redmine_qbo has /invoices/:id for the PDF)
resources :qbo_invoices, only: [:new, :create, :edit, :update] do
  member do
    post :send_email
  end
  collection do
    get :import_options
  end
end

# Receive payment pages, and a customer's payments (/qbo_payments?customer_id=)
resources :qbo_payments, only: [:index, :new, :create, :show] do
  member do
    get :pdf
  end
  collection do
    get :sync
    get :open_invoices
  end
end

# QuickBooks product/service list (moved from redmine_qbo_lineitems; same URLs)
resources :items do
  collection do
    get :autocomplete
    get :sync
  end
end

# QuickBooks income accounts
resources :accounts do
  collection do
    patch :set_default
    get :sync
  end
end

# Business report (estimates, invoices, payments and hours for a period)
get 'qbo_reports', to: 'qbo_reports#index', as: :qbo_reports

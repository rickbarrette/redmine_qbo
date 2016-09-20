#The MIT License (MIT)
#
#Copyright (c) 2016 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

# Main Quickbooks landing page
get 'qbo', :to=> 'qbo#index'

#authentication
get 'qbo/authenticate', :to => 'qbo#authenticate'
get 'qbo/oauth_callback', :to => 'qbo#oauth_callback'

#manual sync
get 'qbo/sync', :to => 'qbo#sync'

# Estimate & Invoice PDF
get 'qbo/estimate/:id', :to => 'estimate#show', as: :estimate
get 'qbo/invoice/:id', :to => 'invoice#show', as: :invoice

#manual billing
get 'qbo/bill/:id', :to => 'qbo#bill', as: :bill

#customer issue view
get 'customers/view/:token', :to => 'customers#view', as: :view

#payments
resources :payments

#webhook
post 'qbo/webhook', :to => 'qbo#qbo_webhook'

#ajax
get "update_vehicles" => 'vehicles#update_vehicles', as: 'update_vehicles'

# Nest Vehicles under customers
resources :customers do
  resources :vehicles
end

#allow for just vehicles too
resources :vehicles

# autocomplete
match '/customers/auto_complete', :to => 'customers#auto_complete', :via => :get, :as => 'customers_auto_complete'

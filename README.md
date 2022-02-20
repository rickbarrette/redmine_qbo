# Redmine Quickbooks Online

A plugin for Redmine to connect to Quickbooks Online

The goal of this project is to allow Redmine to connect with Quickbooks Online to create `Time Activity Entries` for completed work when an Issue is closed.

#### Disclaimer

Note: Although the core functionality is complete, this project is still under heavy development. I am still working on refining everthing and adding other features. Tags should be stable

Use tags Version 1.0.0 & up for Redmine 4+ and Version 0.8.1 for Redine 3

#### Features
* Issues can be assigned to a `Customer` via drop down in the edit Issue form
* The `Employee` for the Issue is assigned via the assigned Redmine User
  - This is set via a drop down in the user admistration page.
* IF an `Issue` has been assined a `Customer` when an Issue is closed the following will happen:
  - A new `Time Activity` will be billed agaist the `Customer` assinged to the issue for each Redmine Time Entery. 
    + Time Entries will be totalled up by Activity name. This will allow billing for diffrent activities without having to create seperate Issues.
    + The Time Activity names are used to lookup `Items` in Quickbooks.
    + IF there isn'tany Items that match the Activity name it will be skipped, and will not be billed to the `Customer` 
  - Labor Rates are set by the `Item` in Quickbooks
* `Payments` Can be created via the Redmine application menu
* `Customers` Can be created via the Redmine application menu
  - `Customers` can be searched
  - Basic information for the `Customer` can be viewed/edit via the Customer page
* Webhook Support
  - `Invoices` are automaticly attached to an Issue if a line item has a hashtag number in a `Line Item`
    + `Invoice` Custom Fields are matched Issue Custom Fileds and are automaticly updated in Quickbooks. For example, this is usefull for extracting the Mileage In / Out from the Issue and updating the Invoice with the information.
  - `Customers` are automaticly updated in local database

## Prerequisites

* Sign up to become a developer for Intuit https://developer.intuit.com/
* Create your own aplication to obtain your API keys
* Set up webhook service to https://redmine.yourdomain.com/qbo/webhook
  - See https://developer.intuit.com/docs/0100_accounting/0300_developer_guides/webhooks

## The Install

1. To install, clone this repo into your plugin folder

  `git clone git@github.com:rickbarrette/redmine_qbo.git` 
  
2. Migrate your database

  `rake redmine:plugins:migrate RAILS_ENV=production`
  
3. Navigate to the plugin configuration page and suppy your own OAuth key & secret. 

4. After saving your key & secret, you need to click on the Authenticate link on the plugin configuration page to authenticate with QBO.

5. Assign an Employee to each of your users via the User Administration Page

## Usage

  To enable automatic `Time Activity` entries for an Issue , you need only to assign a `Customer` to an Issue via drop downs in the issue creation/update form.

Note: After the inital synchronization, this plugin will recieve push notifications via Intuit's webhook service.

## TODO
  * Abiltiy to add line items to a ticket in a dynamic table so they can be added to the invoice upon closing of the issue
  * Customer Deletion
  * Email Customer updates, provding a link that would: bypass the login page, go directly to the issue directing them to, and allow them to view only that issue. 
  * Add Setting for Sandbox Mode
  * Refactor Models prefixed with Qbo...
  * Seperate Vehicles into a seperate plugin
  * Make HTML Pretty 
  * Intergrate Customer Search into Redmine Search
  * Fix Issue sort by Customer
  * MORE Stuff...

## License

The MIT License (MIT)

Copyright (c) 2022 rick barrette

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

#Redmine Quickbooks Online

A simple plugin for Redmine to connect to Quickbooks Online

The goal of this project is to allow redmine to connect with Quickbooks Online to create time activity entries for completed work when an issue is closed.

`Note: This project is under heavy development. Currently the initial functionality goal has been meet, however I am still working on adding other features. Tags should be stable`

####How it works
* Issues can be assigned to a QBO Customer and QBO Service Item via drop down in issues form
  - The `QBO Employee` for the issue is assigned via the assigned redmine user
  - IF an `Issue` has been assined a `QBO Customer`, `QBO Service Item` & `QBO Employee` when an `Issue` is closed the following will happen:
  - A new `QBO Time Activity` agaist the `QBO Customer` will be created using the total spent hours logged agaist an `Issue`.
  - The rate will be the set via the `QBO Service Item` price
* `Issues` with the Tracker `Quote` will generate an estimate based on the estimated hours and `QBO Service Item` cost.
  - Needs to have a `QBO Customer` & `QBO Service Item` Assiged
* Users will be assigned a `QBO Employee` via a drop down in the user admistration page.

##Prerequisites

* Sign up to become a developer for Intuit https://developer.intuit.com/
* Create your own aplication to obtain your API keys

##The Install

1. To install, clone this repo into your plugin folder

  `git clone git@github.com:rickbarrette/redmine_qbo.git` 
  
2. Migrate your database

  `rake redmine:plugins:migrate RAILS_ENV=production`
  
3. Navigate to the plugin configuration page and suppy your own OAuth key & secret. 

  ![Alt plugin_config](/Screenshots/plugin_config.png)

4. After saving your key & secret, you need to click on the Authenticate link on the plugin configuration page to authenticate with QBO.

5. Assign an Employee to each of your users via the User Administration Page

  ![Alt plugin_user_edit](/Screenshots/plugin_user_edit.png)
  
## Usage

  To enable automatic `QBO Time Activity` entries for an `Issue` , you need only to assign a `QBO Customer` and `QBO Item` to an `Issue` via drop downs in the creation/update form.
  
  ![Alt plugin_issue-edit](/Screenshots/plugin_issue_edit.png)

Note: Customers, Employees, and Service Items with automaticly update during normal usage of redmine i.e. a page refresh. You can also manualy force redmine to sync its database with QBO clicking the sync link in the Quickbooks top menu page 

  ![Alt plugin_top_menu](/Screenshots/plugin_top_menu.png)

## TODO
  * Abiltiy to add line items to a ticket in a dynamic table so they can be added to the invoice upon closing of the issue
  * Customer ~~Creation~~, ~~Update~~, Deletion
  * Email Customer updates, provding a link that would: bypass the login page, go directly to the issue directing them to, and allow them to view only that issue. 
  * Add a rake file to create required Trackers or statuses required
  * Add Setting for Sandbox Mode

##License

The MIT License (MIT)

Copyright (c) 2016 rick barrette

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

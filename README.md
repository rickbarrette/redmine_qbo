#Redmine Quickbooks Online

##About

This is a simple plugin for Redmine to connect to Quickbooks Online

The goal of this project is to allow redmine to connect with Quickbooks Online to create time activity entries for completed work when an issue is closed.

####How it works
* A QBO customer and service item can be assigned to a redmine issue.
* A QBO employee can be assigned to a redmine user
* When a issue is closed, the following things happen:
  - The plugin checks to see if the user assinged to the issue has a QBO employee assinged to them
  - The plugin checks to see if the issue has a QBO customer & service item attached
  - If the above statements are true, then a new QBO Time Activity is created
  - The total time for the Time Activity will be total spent time.
  - The rate will be the set be the service item

##Prerequisites

* Sign up to become a developer for Intuit https://developer.intuit.com/
* Create your own aplication to obtain your API keys

##The Install

1. To install, clone this repo into your plugin folder 

  ' git clone git@github.com:rickbarrette/redmine_qbo.git ' 
  
2. Migrate your database

  ' rake redmine:plugins:migrate RAILS_ENV=production '
  
3. Navigate to the plugin configuration page (https://your.redmine.com/settings/plugin/redmine_qbo) and suppy your own OAuth key & secret. 
4. After saving your key & secret, you need to click on the Authenticate link on the plugin configuration page to authenticate with QBO.
5. Enjoy

Note: Customers and Employees with automaticly update during normail usage of redmine i.e. a page refresh

Note:nService Items do not automaticly update at this time, if you add/remove service items you will need to synchronize your database with QBO by clicking the sync link in the Quickbooks top menu (https://your.redmine.com/redmine/qbo)

##License

The MIT License (MIT)

Copyright (c) 2016 rick barrette

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

#redmine_qbo

##About

This is a simple plugin for Redmine to connect to Quickbooks Online

The goal of this project is to allow redmine to connect with Quickbooks Online to create time activity entries for completed work when an issue is closed.

####How it works
* A QBO customer and service item can now be assigned to an issue. 
* When a issue is closed, a new QBO Time Activity is created
  - The total time for the Time Activity will be total spent time.
  - The rate will be the set be the service item

*Warning: * This is under heavy development

##Prerequisites

Sign up to become a developer for Intuit https://developer.intuit.com/

##The Install

To install, clone into your plugin folder and migrate your database. Then navigate to the plugin configuration page (https://your.redmine.com/settings/plugin/redmine_qbo) and suppy your own OAuth key & secret. 

After saving your key & secret, you need to click on the Authenticate link on the plugin configuration page to authenticate with QBO.

Once you are authenticated with QBO, you need to synchronize your database with QBO by clicking the sync link in the Quickbooks top menu (https://your.redmine.com/redmine/qbo)

##License

The MIT License (MIT)

Copyright (c) 2016 rick barrette

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

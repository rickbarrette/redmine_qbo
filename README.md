# Redmine QuickBooks Online

A plugin for Redmine to connect to QuickBooks Online.

The goal of this project is to allow Redmine to connect with QuickBooks Online to create Time Activity Entries for billable hours logged when an Issue is closed.

## Disclaimer

**Note:** Although the core functionality is complete, this project is still under development and the master branch may be unstable. Tags should be stable and are recommended.

## Compatibility

| Plugin Version | Redmine Version |
| :--- | :--- |
| Version 2026.1.0+ | Redmine 6.1 |
| Version 2.0.0+ | Redmine 5 |
| Version 1.0.0+ | Redmine 4 |
| Version 0.8.1 | Redmine 3 |

## Features

* **Customer Assignment:** Issues can be assigned to a Customer via a dropdown in the edit Issue form.
    * Once a customer is attached to an Issue, you can attach an Estimate to the issue via a dropdown menu.
* **Employee Mapping:** An Employee is assigned to a Redmine User via a dropdown in the User Administration page.
* **Automatic Billing:** If an Issue has been assigned a Customer, the following happens when the Issue is closed:
    * A new Time Activity will be billed against the Customer assigned to the issue for each Redmine Time Entry.
    * Time Entries will be totalled up by Activity name. This allows billing for different activities without having to create separate Issues.
    * The Time Activity names are used to dynamically lookup Items in QuickBooks.
    * If there are no Items that match the Activity name, it will be skipped and will not be billed to the Customer.
    * Labor Rates are set by the corresponding Item in QuickBooks.
* **Customer Management:** Customers can be created via the New Customer Page.
    * Customers can be searched by name or phone number.
    * Basic information for the Customer can be viewed/edited via the Customer page.
* **Webhook Support:**
    * **Invoices:** Automatically attached to an Issue if a line item contains a hashtag number (e.g., `#123`).
    * **Custom Fields:** Invoice Custom Fields are matched to Issue Custom Fields and are automatically updated in QuickBooks. (Useful for extracting Mileage In/Out from the Issue to update the Invoice).
    * **Sync:** Customers are automatically updated in the local database.

## Prerequisites

* Sign up to become a developer for Intuit: https://developer.intuit.com/
* Create your own application to obtain your API keys.
* Set up the webhook service to `https://redmine.yourdomain.com/qbo/webhook`

## Installation

1. **Clone the plugin:**
   Clone this repo into your plugin folder and checkout a tagged version.
   ```bash
   cd path/to/redmine/plugins
   git clone git@github.com:rickbarrette/redmine_qbo.git
   cd redmine_qbo
   git checkout <tag>
   ```

2.  **Install dependencies:** *Crucial for Redmine 6 / Rails 7 compatibility.*
    
    Bash
    
    ```
    bundle install
    ```
    
3.  **Migrate your database:**
    
    Bash
    
    ```
    bundle exec rake redmine:plugins:migrate RAILS_ENV=production
    ```
    
4.  **Restart Redmine:** You must restart your Redmine server instance for the plugin and hooks to load.
    
5.  **Configuration:**
    
    *   Navigate to the plugin configuration page (`Administration > Plugins > Configure`).
        
    *   Supply your own OAuth Key & Secret.
        
    *   After saving the Key & Secret, click the **Authenticate** link on the configuration page to connect to QBO.
        
6.  **User Mapping:**
    
    *   Assign an Employee to each of your users via the **User Administration Page**.
        

## Usage

To enable automatic Time Activity entries for an Issue, you simply need to assign a Customer to an Issue via the dropdowns in the issue creation/update form.

**Note:** After the initial synchronization, this plugin will receive push notifications via Intuit's webhook service.

## TODO

*   Add Setting for Sandbox Mode
    
*   Separate Vehicles into a separate plugin (I use Redmine for my automotive shop management 😉)
    
*   MORE Stuff as I make it up...
    

## License

> The MIT License (MIT)
>
> Copyright (c) 2016 - 2026 Rick Barrette
>
> Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
>
> The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
>
> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
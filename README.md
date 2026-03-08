# Redmine QuickBooks Online Plugin

A plugin for **Redmine** that integrates with **QuickBooks Online (QBO)** to automatically create **Time Activity entries** from billable hours logged on Issues.

When an Issue associated with a Customer is closed, the plugin generates corresponding Time Activities in QuickBooks based on the Redmine Time Entries recorded for that Issue.

---

# Disclaimer

The core functionality is implemented, but the project is **under active development**.

The `master` branch may contain unstable changes.  
For production deployments, **use a tagged release**.

---

# Compatibility

| Plugin Version | Redmine Version |
| :--- | :--- |
| Version 2026.1.0+ | Redmine 6.1 |
| Version 2.0.0+ | Redmine 5 |
| Version 1.0.0+ | Redmine 4 |
| Version 0.8.1 | Redmine 3 |

---

# Features

## Issue Billing Integration

*   Assign a **QuickBooks Customer** to a Redmine Issue.
    
*   Optionally associate a **QuickBooks Estimate** with the Issue.

*   Automatically associates a **QuickBooks Invoice** with the Issue.
    

---

## Automatic Time Activity Creation

When an Issue with an assigned Customer is closed:

*   A **Time Activity** is created in QuickBooks for each relevant Redmine Time Entry.
    
*   Time Entries are **grouped by Activity name**.
    
*   Activity names are used to **dynamically match Items in QuickBooks**.
    
*   If no matching Item exists, the activity is **skipped**.
    
*   **Labor rates** are determined by the associated QuickBooks Item.
    

---

## Employee Mapping

Redmine Users can be mapped to **QuickBooks Employees** through the **User Administration** page.

This ensures Time Activities are recorded under the correct employee in QuickBooks.

---

## Customer Management

The plugin provides basic Customer management:

*   Create Customers directly from Redmine
    
*   Search Customers by **name or phone number**
    
*   View and edit Customer information
    

Customers are synchronized with QuickBooks.

---

## Webhook Support

The plugin listens for **QuickBooks webhook events**.

Supported automation:

### Invoice Linking

Invoices containing an Issue reference (e.g. `#123`) automatically attach to the corresponding Issue.

### Custom Field Synchronization

Invoice custom fields can be mapped to Issue custom fields.

Example use case:

*   Mileage In/Out recorded in Redmine
    
*   Automatically synchronized to the QuickBooks invoice.
    

### Customer Synchronization

Customer records are automatically updated in the local database when changes occur in QuickBooks.

---

## Plugin Hooks

The plugin exposes several hooks for extending functionality through companion plugins.

Example:

`redmine_qbo_vehicles`  
Adds support for tracking **customer vehicles** associated with Issues.

Available hooks:

|Type|Hook|Note
|--|--|--|
View Hook|:pdf_left, { issue: issue }  | Used to add text to left side of PDF
View Hook|:pdf_right, { issue: issue }  | Used to add text to right side of PDF
Hook|process_invoice_custom_fields, { issue: issue, invoice: invoice }  | Used to process invoice custom fields
View Hook|:show_customer_view_right, { customer: customer } | Used to show partials on right side of customer view
Hook| :qbo_additional_entities | Used to add additional entites to be processed by the WebhookProcessJob
Hook| :qbo_full_sync | Used to add a Class to be called by the QboSyncDispatcher

---

# Prerequisites

Before installing the plugin:

1.  Create a QuickBooks developer account:
    

[https://developer.intuit.com/](https://developer.intuit.com/)

2.  Create an **Intuit application** to obtain:
    

*   Client ID
    
*   Client Secret
    

3.  Configure the QuickBooks webhook endpoint:
    

https://redmine.yourdomain.com/qbo/webhook

---

# Installation

## 1\. Clone the Plugin

Install the plugin into your Redmine plugins directory.

```bash
cd /path/to/redmine/plugins  
git clone https://github.com/rickbarrette/redmine_qbo.git  
cd redmine_qbo  
git checkout <tag>
```

Use a **tagged release** for stability.

---

## 2\. Install Dependencies

```bash
bundle install
```

Required for **Redmine 6 / Rails 7 compatibility**.

---

## 3\. Run Database Migrations

```bash
bundle exec rake redmine:plugins:migrate RAILS_ENV=production
```

---

## 4\. Restart Redmine

Restart your Redmine server so the plugin and hooks are loaded.

---

# Configuration

1.  Navigate to:
    

Administration → Plugins → Configure

2.  Enter your **QuickBooks Client ID and Client Secret**.
    
3.  Save the configuration.
    
4.  Click **Authenticate** to complete the OAuth connection with QuickBooks Online.
    

Once authentication succeeds, the plugin performs an **initial synchronization**.

---

# User Mapping

Each Redmine user must be mapped to a QuickBooks Employee.

Navigate to:

Administration → Users

Then assign the corresponding **QuickBooks Employee** to each user.

---

# Usage

To enable automatic billing:

1.  Assign a **Customer** to an Issue.
    
2.  Log billable time using **Redmine Time Entries**.
    
3.  Close the Issue.
    

When the Issue is closed, the plugin automatically generates the corresponding **Time Activity entries in QuickBooks Online**.

After the initial synchronization, the plugin receives updates through **Intuit webhooks**.

---

# Troubleshooting

### Time Activities Not Created

Verify that:

*   The Issue has a **Customer assigned**
    
*   Time Entries exist for the Issue
    
*   Activity names match **QuickBooks Item names**
    

---

### Webhooks Not Triggering

Ensure the QuickBooks webhook endpoint is reachable:

https://redmine.yourdomain.com/qbo/webhook

Also verify webhook configuration in the Intuit developer dashboard.

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
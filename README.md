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

### Customer Synchronization

Customer records are automatically updated in the local database when changes occur in QuickBooks.

### Estimates, Invoices and Payments

Estimates and invoices keep their number, date, customer, total and **man-hours** (the quantities of the labor products/services, including lines inside bundles). Payments keep their customer, date, amount and unapplied amount. These cached figures feed the business report.

---

## Billing: Estimates, Invoices and Payments

* **New estimate** from the customer page: Create Estimate opens the Redmine editor. The customer page no longer links to QuickBooks' estimate or payment screens; the customer's name still opens their QuickBooks account page as a fallback.
* **Edit** any estimate from the Edit link next to it on the customer page or the issue page.
* **Duplicate** an estimate to start a similar one: same customer, lines, subtotals, VIN and messages, dated today, with the current user as sales person.
* **Read-only once linked to an issue**: an estimate that an issue is linked to can be viewed, emailed and duplicated, but not changed, so the work doesn't drift from what was quoted. The list shows a View link for these instead of Edit.
* **Read-only once billed**: an estimate that's Converted or Closed in QuickBooks, or linked to an invoice, can't be changed here either (including redmine_qbo_lineitems' estimates once they're invoiced). Its page lists the invoices it's on; it can still be viewed, emailed and duplicated, and it shows View instead of Edit in lists.
* **Create issues** from an estimate's labor lines (moved here from redmine_qbo_calendar): each line with one of the **labor products/services** (e.g. Labor) becomes an issue with the line's description as subject and its quantity as estimated hours. Pick the project, trackers, templates and shared custom fields first. Lines already turned into issues can't be created twice, and issues from the same estimate are related to each other. Opened from an appointment, the issues get the appointment's dates, technician and vehicle.
* **Email** the estimate with QuickBooks' own estimate email, with **Save and send** or the Email link.
* The page follows QuickBooks' estimate screen: customer, customer email, billing address, estimate date, expiration date, estimate number, then the product/service lines (#, product/service, description, qty, rate, amount, tax), the message displayed on the estimate, the memo, and the totals.
* Lines work like QuickBooks: the product list opens when the box is clicked, picking a product fills in its description, rate and tax, typing an amount works out the rate, a spare empty line is always at the bottom, and lines are reordered by dragging them by the handle.
* A line with a description but no product or rate is saved as a description-only line, e.g. the estimate notes on the first line.
* **Add subtotal** puts a subtotal line after the last filled line. A subtotal totals the lines above it, back to the previous subtotal, and can be dragged like any line. It's saved the way QuickBooks saves subtotals from its own screen, as a line reading "Subtotal: $342.60" that prints where it was placed, so the PDF keeps its layout.
* Sales tax is worked out by QuickBooks when the estimate is saved.

### Invoices

* **Create invoice** on an estimate's page makes an invoice from it (customer, lines, subtotals, VIN), like QuickBooks' "Create invoice". **Create invoice** on the customer page starts a blank one, and the Edit link next to each invoice on the customer page opens it.
* **Import time & estimates** lists the customer's billable QuickBooks time (the time activities redmine_qbo makes from an issue's time entries) and their open estimates (e.g. the ones redmine_qbo_lineitems makes for parts that weren't quoted).
  * Tick the time to bill and, under **Replace these lines**, the lines it replaces (e.g. the estimate's labor lines). Only lines with one of the **labor products/services** from the plugin settings are offered there. The time goes where the first ticked line was and the ticked lines are removed, so the invoice reads in the same order.
  * Ticked estimates go right after the time for the same issue: a redmine_qbo_lineitems estimate starting "Added from: Install #116: …" lands after the time for #116, without that note line, since the time line already names the issue. Estimates with no matching time keep the note and go at the end.
  * **Undo import** puts the lines back until the invoice is saved.
* **An estimate is billed once**: an estimate that's on an invoice (linked to one, or closed) or was rejected can't be made into an invoice or imported, and its page shows the invoice it's billed on. This is checked against QuickBooks again when the invoice is saved, so an estimate invoiced meanwhile (in another tab, by someone else, or in QuickBooks) stops the save.
* Time lines are linked to their time activities, so QuickBooks marks the time as billed. Estimates the invoice was made from, or imported into it, are linked and closed when it's saved.
* **VIN and mileage from the work orders**: the issues behind an invoice are the ones its time lines and lineitems estimates name. When they're imported, the VIN box takes their vehicle's VIN and a **Mileage** box (shown when QuickBooks has a text custom field named like "Mileage") takes the highest value of the issues' Mileage custom field, both supplied by redmine_qbo_vehicles. With redmine_qbo_vehicles, an invoice whose work orders are for more than one vehicle isn't saved.
* **Sales person**: an invoice credits the sales person on the estimate it was made from (the first linked estimate that names one); if none does, the user who writes the invoice.
* Invoices with a payment applied open read-only. The due date is left to QuickBooks (from the customer's terms) unless one is picked. The "default message shown on invoices" fills in the message.

### Payments

* **Receive payment** on the customer page or on an unpaid invoice: the customer, payment date, payment method (QuickBooks' list: Cash, Check...), reference number (e.g. the check number), amount and a memo.
* Tick open invoices to fill in the amount (their open balances added up) and pay just those; the header box ticks them all.
* With none ticked, the payment is applied to the customer's open invoices **oldest first**, like QuickBooks does; the page shows how it will be split as the amount is typed, and it's worked out again from QuickBooks when saving. Anything more than the open balances stays as a credit.
* Tick **Deposit** to keep the whole payment as a credit on the customer's account without paying any invoice (also what happens when there are no open invoices).
* The saved payment's page shows where it was applied and has **Print**, QuickBooks' payment PDF.
* **Payments** on the customer page lists all of the customer's payments from QuickBooks, newest first: date, method, reference no., the invoices each was applied to (or Deposit), memo, amount and what's still unapplied, with totals. Each date opens the payment's page and **Print** opens its PDF.

### Business report

**Business report** in the top menu compares, for a period (this or last month, quarter or year, or custom dates):

* **Sales**: estimates written, invoices written and payments received (totals and counts), invoiced vs. estimated, collected vs. invoiced, and what's still owed on those invoices.
* **Hours**: estimated hours on estimates, issues' estimated time, invoiced hours on invoices and time spent, with invoiced vs. spent and spent vs. estimated.
* **By month**: every figure month by month, with totals.

Estimates, invoices and payments count by their QuickBooks date. Issues' estimated time counts issues created in the period, leaving out parents so subtasks aren't counted twice. Spent time counts time logged in the period. While estimates, invoices or payments are syncing, the report says so (with how many have been read) and refreshes every 30 seconds; the settings page's Synchronization table shows the same per type. Estimates and invoices synced before these figures were added have no total or hours until a full sync (the report says how many); run one again after changing the labor products/services.

### QuickBooks custom fields

Nothing is configured in Redmine. The plugin reads QuickBooks' sales form settings, and the custom fields on the 20 most recently changed estimates, and finds the fields by name:

* A text field whose name contains **VIN** gets the VIN box. The customer's vehicles (from redmine_qbo_vehicles) are offered as choices.
* A text field whose name contains **Sales** or **Rep** (e.g. "Sales Person", "Salesperson", "Sales Rep") gets the name of the Redmine user who creates the estimate. Editing an estimate keeps its sales person.

QuickBooks only shares its first three **text** custom fields with apps; dropdown custom fields can't be read or filled in. If your sales person field is a dropdown, change it to a text field in QuickBooks (Settings → Custom fields).

Newer QuickBooks custom fields (made under Settings → Custom fields) aren't listed in QuickBooks' settings, so the plugin asks QuickBooks for all custom fields on estimates and finds them on the most recently changed ones. If a new field isn't found, fill it in on one estimate in QuickBooks, then refresh.

The settings are read once an hour (every five minutes while the VIN or sales person field is missing). After adding or renaming a custom field in QuickBooks, an administrator can use **Refresh QuickBooks fields** on the estimate page, which also lists the fields QuickBooks shares. Newer QuickBooks custom fields (e.g. on Advanced and sandbox companies) may not be listed in its settings; they're found once they're filled in on at least one estimate.

Estimate numbers can't be typed. QuickBooks numbers new estimates; when its "Custom transaction numbers" setting is on, the next number is filled in when the estimate is created. The "default message shown on estimates" fills in the message on new estimates.

### Products/services and accounts

Administration → Items lists the QuickBooks product/service list (synced from QuickBooks, and pushed back when an item is added or edited here). Accounts are reached from there. The plugin settings show the counts, the default income account for new items, and Sync buttons. These moved here from redmine_qbo_lineitems with the same URLs.

### What is left to QuickBooks

* Estimates with bundles open read-only, so a bundle can't be broken apart by accident.
* The sales person box is read-only: it shows who created the estimate.
* Discounts on an estimate are kept as they are; they can't be edited here.
* If an estimate was changed in QuickBooks after it was opened in Redmine, saving stops and asks to reload it, so nobody's changes are overwritten.

### Billing Settings and Permissions

1. Permissions

    1. Navigate to Administration -> Roles and permissions.
    2. Assign these global permissions as needed:
        * **Write estimates**: create and edit estimates
        * **Email estimates**: email estimates to customers (Save and send, and the Email link)
        * **Create issues from estimates**: the Create issues page (was redmine_qbo_calendar's "Create issues from appointment estimates")
        * **View payments**: a customer's Payments list, the payment page and its PDF
        * **Receive payments**: the Receive payment page, plus everything View payments allows
        * **View business reports**: the Business report
        * **Write invoices**: create and edit invoices, and import time and estimates into them
        * **Email invoices**: email invoices to customers

2. Settings (Administration -> Plugins -> Configure)
    * **Estimates expire after (days)**: new estimates get an expiration date this many days after the estimate date (e.g. 30). Leave blank for none.
    * **Labor products/services** (e.g. Labor): one list used three ways. An estimate's lines with them can become issues (their quantities are also the estimate's labor hours, which an appointment's hours can't be less than); an invoice's lines with them are offered under Replace these lines when time is imported; and their quantities are the hours on estimates and invoices in the business report. While none are chosen, products/services named Labor are used.
    * **Issues from estimates**: the default project and the default tracker.
    * Item and account counts, the default income account and their syncs are under Synchronization.

3. Writing an estimate

    1. Open the customer and click **Create Estimate**.
    2. Fill in the lines. Type in the product/service box or click it to pick from the list.
    3. Click **Save**, or **Save and send** to email it to the customer email.

## Plugin Hooks

The plugin exposes several hooks for extending functionality through companion plugins.

Example:

`redmine_qbo_vehicles`  
Adds support for tracking **customer vehicles** associated with Issues.

Available hooks:

|Type|Hook|Note
|--|--|--|
View Hook|:view_customers_show_contextual, { customer: @customer } | Used to add action links to the customer page's top-right action area (return links styled like Redmine's, e.g. `link_to sprite_icon('add', 'Label'), path, class: 'icon icon-add'`). Replaces `customer_actions_top` / `customer_actions_bottom`
View Hook|:pdf_left, { issue: issue }  | Used to add text to left side of PDF
View Hook|:pdf_right, { issue: issue }  | Used to add text to right side of PDF
View Hook|:show_customer_view_right, { customer: customer } | Used to show partials on right side of customer view
Hook| :qbo_additional_entities | Used to add additional entites to be processed by the WebhookProcessJob
Hook| :qbo_full_sync | Used to add a Class to be called by the QboSyncDispatcher
Hook|:qbo_billing_issue_values, { issues: } | Return `{ field => { issue_id => value } }` for the work orders behind an invoice, e.g. `{ vin: { 116 => "1C4..." } }` (redmine_qbo_vehicles). Importing time or estimates fills the VIN box when the work orders share one VIN, and the mileage box with the highest `mileage` value (redmine_qbo_vehicles reads it from the issue custom field named "Mileage")
Hook|:qbo_billing_validate, { document:, form:, issues: } | Return an error message (or several) to stop an estimate or invoice from saving, e.g. redmine_qbo_vehicles: one vehicle per invoice
Hook|:qbo_billing_issue_defaults, { estimate:, params: } | Return `start_date`, `due_date`, `assignee`, `project`, `description`, `return_path`, `return_label`, plus any values your own fields need (e.g. redmine_qbo_calendar's `vehicle_id`), for issues created from an estimate (redmine_qbo_calendar, when opened from an appointment)
Hook|:qbo_billing_build_issue, { issue:, estimate:, defaults: } | Set your plugin's own fields on each issue created from an estimate, before it's saved (redmine_qbo_vehicles sets the vehicle: the one in `defaults`, or the customer's vehicle whose VIN is on the estimate)
Hook|:qbo_billing_issues_created, { estimate:, issues:, params: } | Called after issues are created from an estimate
Hook|:qbo_billing_default_vin, { customer:, issues: } | Return the VIN a new estimate or invoice starts with (an invoice made from an estimate keeps the estimate's VIN; `issues` are that estimate's work orders). redmine_qbo_vehicles: the work orders' vehicle when they share one, else the customer's only vehicle
Hook|:qbo_billing_vin_options, { customer: } | Return `[{ vin:, name: }, ...]` to suggest in the estimate/invoice VIN box; one suggestion fills an empty box (redmine_qbo_vehicles: the customer's vehicles)
View|checkboxes with `data-new-issue-param="issue[field]"` on the customer page | Ticking one adds `issue[field]=value` to the New issue link, one per field (redmine_qbo's estimates, redmine_qbo_vehicles' vehicles)
View Hook|:view_qbo_estimate_contextual, { estimate_id:, customer_id:, vin:, doc_number: } | Adds links to an estimate page's action area (e.g. redmine_qbo_calendar's Add appointment)

Other plugins create estimates with `RedmineQboBilling::EstimateWriter.create_estimate(customer:, lines:, private_note:, vin:, mileage:, user:)`; each line is a hash of `description`, `item_id`, `quantity`, `rate` and `taxable`.

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

## 1. Clone the Plugin

Install the plugin into your Redmine plugins directory.

```bash
cd /path/to/redmine/plugins  
git clone https://github.com/rickbarrette/redmine_qbo.git  
cd redmine_qbo  
git checkout <tag>
```

Use a **tagged release** for stability.

---

## 2. Install Dependencies

```bash
bundle install
```

Required for **Redmine 6 / Rails 7 compatibility**.

---

## 3. Run Database Migrations

```bash
bundle exec rake redmine:plugins:migrate RAILS_ENV=production
```

---

## 4. Restart Redmine

Restart your Redmine server so the plugin and hooks are loaded.

---

# Configuration

1.  Navigate to:
    

Administration → Plugins → Configure

2.  Enter your **QuickBooks Client ID and Client Secret**.
    
3.  Save the configuration.
    
4.  Click **Authenticate** to complete the OAuth connection with QuickBooks Online.
    

Once authentication succeeds, the plugin performs an **initial synchronization**.

The settings page has three sections:

* **QuickBooks connection**: client ID and secret, webhook token, sandbox, when the access token expires, and Connect to QuickBooks.
* **Synchronization**: customers, employees, estimates, invoices, payments, products/services (items) and accounts, with how many of each are stored, when each last synced and a **Sync** link for each (it re-reads every record of that type). **Sync changes** reads only what changed since the last sync; **Full sync** re-reads everything. The default income account for new products/services is shown here too.
* **Billing**: estimate expiration, the labor products/services and the issues-from-estimates defaults.

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
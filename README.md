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

---

## Billing: Estimates, Invoices and Payments

* **New estimate** from the customer page (the Create Estimate link opens the Redmine editor instead of QuickBooks).
* **Edit** any estimate from the Edit link next to it on the customer page or the issue page.
* **Duplicate** an estimate to start a similar one: same customer, lines, subtotals, VIN and messages, dated today, with the current user as sales person.
* **Read-only once linked to an issue**: an estimate that an issue is linked to can be viewed, emailed and duplicated, but not changed, so the work doesn't drift from what was quoted. The list shows a View link for these instead of Edit.
* **Create issues** from an estimate's labor lines (moved here from redmine_qbo_calendar): each line whose item matches an **estimate item code** (e.g. Labor) becomes an issue with the line's description as subject and its quantity as estimated hours. Pick the project, trackers, templates and shared custom fields first. Lines already turned into issues can't be created twice, and issues from the same estimate are related to each other. Opened from an appointment, the issues get the appointment's dates, technician and vehicle.
* **Email** the estimate with QuickBooks' own estimate email, with **Save and send** or the Email link.
* The page follows QuickBooks' estimate screen: customer, customer email, billing address, estimate date, expiration date, estimate number, then the product/service lines (#, product/service, description, qty, rate, amount, tax), the message displayed on the estimate, the memo, and the totals.
* Lines work like QuickBooks: the product list opens when the box is clicked, picking a product fills in its description, rate and tax, typing an amount works out the rate, a spare empty line is always at the bottom, and lines are reordered by dragging them by the handle.
* A line with a description but no product or rate is saved as a description-only line, e.g. the estimate notes on the first line.
* **Add subtotal** puts a subtotal line after the last filled line. A subtotal totals the lines above it, back to the previous subtotal, and can be dragged like any line. It's saved the way QuickBooks saves subtotals from its own screen, as a line reading "Subtotal: $342.60" that prints where it was placed, so the PDF keeps its layout.
* Sales tax is worked out by QuickBooks when the estimate is saved.

### Invoices

* **Create invoice** on an estimate's page makes an invoice from it (customer, lines, subtotals, VIN), like QuickBooks' "Create invoice". **Create invoice** on the customer page starts a blank one, and the Edit link next to each invoice on the customer page opens it.
* **Import time & estimates** lists the customer's billable QuickBooks time (the time activities redmine_qbo makes from an issue's time entries) and their open estimates (e.g. the ones redmine_qbo_lineitems makes for parts that weren't quoted).
  * Tick the time to bill and, under **Replace these lines**, the lines it replaces (e.g. the estimate's labor lines). When products/services are set as **Replaced by imported time** in the plugin settings, only lines with one of them are offered there; with none set, every line is. The time goes where the first ticked line was and the ticked lines are removed, so the invoice reads in the same order.
  * Ticked estimates go right after the time for the same issue: a redmine_qbo_lineitems estimate starting "Added from: Install #116: …" lands after the time for #116, without that note line, since the time line already names the issue. Estimates with no matching time keep the note and go at the end.
  * **Undo import** puts the lines back until the invoice is saved.
* **An estimate is billed once**: an estimate that's on an invoice (linked to one, or closed) or was rejected can't be made into an invoice or imported, and its page shows the invoice it's billed on. This is checked against QuickBooks again when the invoice is saved, so an estimate invoiced meanwhile (in another tab, by someone else, or in QuickBooks) stops the save.
* Time lines are linked to their time activities, so QuickBooks marks the time as billed. Estimates the invoice was made from, or imported into it, are linked and closed when it's saved.
* **VIN and mileage from the work orders**: the issues behind an invoice are the ones its time lines and lineitems estimates name. When they're imported, the VIN box takes their vehicle's VIN (with redmine_qbo_vehicles) and a **Mileage** box (shown when QuickBooks has a text custom field named like "Mileage") takes the highest value of the issues' Mileage custom field. With redmine_qbo_vehicles, an invoice whose work orders are for more than one vehicle isn't saved.
* **Sales person**: an invoice credits the sales person on the estimate it was made from (the first linked estimate that names one); if none does, the user who writes the invoice.
* Invoices with a payment applied open read-only. The due date is left to QuickBooks (from the customer's terms) unless one is picked. The "default message shown on invoices" fills in the message.

### Payments

* **Receive payment** on the customer page (it replaces the link to QuickBooks' receive payment screen) or on an unpaid invoice: the customer, payment date, payment method (QuickBooks' list: Cash, Check...), reference number (e.g. the check number), amount and a memo.
* Tick open invoices to fill in the amount (their open balances added up) and pay just those; the header box ticks them all.
* With none ticked, the payment is applied to the customer's open invoices **oldest first**, like QuickBooks does; the page shows how it will be split as the amount is typed, and it's worked out again from QuickBooks when saving. Anything more than the open balances stays as a credit.
* Tick **Deposit** to keep the whole payment as a credit on the customer's account without paying any invoice (also what happens when there are no open invoices).
* The saved payment's page shows where it was applied and has **Print**, QuickBooks' payment PDF.
* **Payments** on the customer page lists all of the customer's payments from QuickBooks, newest first: date, method, reference no., the invoices each was applied to (or Deposit), memo, amount and what's still unapplied, with totals. Each date opens the payment's page and **Print** opens its PDF.

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
        * **Write invoices**: create and edit invoices, and import time and estimates into them
        * **Email invoices**: email invoices to customers

2. Settings (Administration -> Plugins -> Configure)
    * **Estimates expire after (days)**: new estimates get an expiration date this many days after the estimate date (e.g. 30). Leave blank for none.
    * **Issues from estimates**: the estimate item codes (also an estimate's labor hours, which an appointment's hours can't be less than), the default project and the default tracker. Until saved here, redmine_qbo_calendar's old values are used.
    * **Replaced by imported time**: the products/services (e.g. Labor) whose invoice lines time can replace. Only those lines are offered under Replace these lines; leave empty to offer every line.
    * Item and account counts, the default income account, and Sync Items / Sync Accounts.

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
Hook|:qbo_billing_issue_values, { issues: } | Return `{ field => { issue_id => value } }` for the work orders behind an invoice, e.g. `{ vin: { 116 => "1C4..." } }` (redmine_qbo_vehicles). Importing time or estimates fills the VIN box when the work orders share one VIN, and the mileage box with the highest mileage (read from the issue custom field named "Mileage")
Hook|:qbo_billing_validate, { document:, form:, issues: } | Return an error message (or several) to stop an estimate or invoice from saving, e.g. redmine_qbo_vehicles: one vehicle per invoice
Hook|:qbo_billing_issue_defaults, { estimate:, params: } | Return `start_date`, `due_date`, `assignee`, `vehicle_id`, `project`, `description`, `return_path`, `return_label` for issues created from an estimate (redmine_qbo_calendar, when opened from an appointment)
Hook|:qbo_billing_issues_created, { estimate:, issues:, params: } | Called after issues are created from an estimate
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
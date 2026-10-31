#The MIT License (MIT)
#
#Copyright (c) 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

# Writes, edits and emails QuickBooks estimates from Redmine, on a page laid out like QuickBooks' estimate screen.
class QboEstimatesController < ApplicationController

  before_action :require_admin, only: :refresh_company
  before_action :authorize_global, except: :refresh_company
  before_action :require_sender_for_save_and_send, only: [:create, :update]
  before_action :load_issue_preview, only: [:issues_preview, :create_issues]

  helper :projects
  helper :custom_fields

  # Saving an estimate can take a few QuickBooks calls; any of them can fail with a message worth showing
  QBO_ERRORS = [RedmineQboBilling::EstimateWriter::Error, Quickbooks::IntuitRequestException,
                Quickbooks::InvalidModelException, Quickbooks::AuthorizationFailure,
                # redmine_qbo raises plain errors when QuickBooks isn't connected or the token can't be refreshed
                RuntimeError].freeze

  # A blank estimate, or a copy of another one (?duplicate=<estimate id>)
  def new
    if params[:duplicate].present?
      @form = RedmineQboBilling::EstimateWriter.duplicate_form(params[:duplicate], user: User.current)
    else
      customer = Customer.find_by(id: params[:customer_id]) if params[:customer_id].present?
      @form = RedmineQboBilling::EstimateWriter.new_form(customer: customer, user: User.current)
    end
  rescue *QBO_ERRORS => e
    flash[:error] = qbo_message(e)
    redirect_back_or_default home_path
  end

  def create
    @form = RedmineQboBilling::EstimateForm.from_params(estimate_params)
    # Shown again if the save fails; the sales person is always the user creating the estimate
    @form.sales_person = User.current.name
    return show_invalid(:new) unless @form.valid?

    saved = RedmineQboBilling::EstimateWriter.save(@form, user: User.current)
    finish_save(saved, l(:notice_estimate_saved_in_quickbooks, number: saved.doc_number))
  rescue *QBO_ERRORS => e
    show_error(e, :new)
  end

  def edit
    @form = RedmineQboBilling::EstimateWriter.load(params[:id])
    @linked_issues = RedmineQboBilling::EstimateWriter.linked_issues(@form.id).visible.to_a
  rescue *QBO_ERRORS => e
    flash[:error] = qbo_message(e)
    redirect_back_or_default home_path
  end

  def update
    @form = RedmineQboBilling::EstimateForm.from_params(estimate_params, id: params[:id])
    @form.sales_person = params.dig(:estimate, :sales_person).to_s
    return show_invalid(:edit) unless @form.valid?

    saved = RedmineQboBilling::EstimateWriter.save(@form, user: User.current)
    finish_save(saved, l(:notice_estimate_saved_in_quickbooks, number: saved.doc_number))
  rescue RedmineQboBilling::EstimateWriter::Conflict => e
    @conflict = true
    show_error(e, :edit)
  rescue *QBO_ERRORS => e
    show_error(e, :edit)
  end

  # Emails an estimate that's already saved (e.g. resending it)
  def send_email
    sent = RedmineQboBilling::EstimateWriter.send_email(params[:id], params[:email])
    flash[:notice] = l(:notice_estimate_sent, number: sent.doc_number, email: sent.bill_email&.address || params[:email])
    redirect_to edit_qbo_estimate_path(params[:id])
  rescue *QBO_ERRORS => e
    flash[:error] = qbo_message(e)
    redirect_to edit_qbo_estimate_path(params[:id])
  end

  # Preview of the issues that can be created from the estimate's labor lines. Each line gets a tracker and
  # (optionally) a template before anything is created. Opened from an appointment, the appointment's dates,
  # technician and vehicle are used (redmine_qbo_calendar's :qbo_billing_issue_defaults).
  def issues_preview
  end

  # Creates the issues selected on the preview page, all or nothing
  def create_issues
    @rows = params[:lines].respond_to?(:to_unsafe_h) ? params[:lines].to_unsafe_h : {}
    @custom_field_values = submitted_custom_field_values
    created = @builder.create_issues(project: @target_project, rows: @rows, custom_field_values: @custom_field_values)

    if created.any?
      Redmine::Hook.call_hook(:qbo_billing_issues_created, { estimate: @estimate, issues: created, params: params })
      # The work is going ahead: a pending estimate becomes Accepted in QuickBooks
      accepted = RedmineQboBilling::EstimateWriter.accept(@estimate.id, user: User.current)
      flash[:notice] = l(:notice_estimate_issues_created, count: created.size)
      flash[:notice] += " #{l(:notice_estimate_accepted, number: @estimate.doc_number)}" if accepted
      redirect_to @return_path
    else
      # Rebuild the fields so the form keeps what was entered
      @field_set = RedmineQboBilling::IssueFieldSet.new(project: @target_project, trackers: @trackers,
                                                        values: @custom_field_values)
      render :issues_preview, status: :unprocessable_entity
    end
  end

  # Customer details for the editor when a customer is picked: email, billing address and the suggestions
  # plugins give for the custom field boxes (RedmineQboBilling.field_options)
  def customer_info
    customer = Customer.find_by(id: params[:customer_id])
    return render(json: {}, status: :not_found) unless customer

    render json: {
      id: customer.id,
      name: customer.name,
      email: RedmineQboBilling::EstimateWriter.customer_email(customer),
      billing_address: RedmineQboBilling::EstimateWriter.customer_address(customer),
      field_options: RedmineQboBilling.field_options(customer)
    }
  end

  # Product/service search for the line table (the QuickBooks item list)
  def items

    term = "%#{ActiveRecord::Base.sanitize_sql_like(params[:q].to_s.strip)}%"
    items = Item.sellable
                .where("name LIKE :t OR sku LIKE :t OR description LIKE :t", t: term)
                .order(:name)
                .limit(25)

    render json: items.map { |item|
      { id: item.id, name: item.name, sku: item.sku, description: item.description,
        price: item.unit_price&.to_s, taxable: item.taxable != false }
    }
  end

  # Re-reads the QuickBooks custom fields and estimate settings (e.g. after renaming a custom field)
  def refresh_company
    RedmineQboBilling::Company.refresh!
    flash[:notice] = l(:notice_estimate_settings_refreshed)
    redirect_back_or_default home_path
  end

  private

  # Everything the issues preview needs: the local estimate, defaults from other plugins, the target project,
  # its trackers, templates and custom fields
  def load_issue_preview
    @estimate = Estimate.find_by(id: params[:id])
    unless @estimate
      EstimateSyncService.new.sync_by_id(params[:id])
      @estimate = Estimate.find_by(id: params[:id])
    end
    return render_404 unless @estimate

    # Values plugins' fields posted with the form (e.g. redmine_qbo_vehicles' vehicle) override their defaults
    @defaults = issue_defaults.merge(submitted_plugin_fields)
    @builder = RedmineQboBilling::EstimateIssueBuilder.new(@estimate, defaults: @defaults)
    @return_path = @defaults[:return_path].presence || edit_qbo_estimate_path(@estimate.id)
    @return_label = @defaults[:return_label].presence || "#{l(:label_estimate)} ##{@estimate.doc_number}"
    @available_projects = Project.allowed_to(User.current, :add_issues).sorted.to_a

    # A project chosen on the page wins, then the one from another plugin (e.g. the appointment's), then the
    # default project from the settings, then the first project the user can add issues to
    chosen = @available_projects.detect { |p| p.id == params[:project_id].to_i } if params[:project_id].present?
    from_hook = @defaults[:project] if @available_projects.include?(@defaults[:project])
    default_project = @available_projects.detect { |p| p.id == RedmineQboBilling::EstimateIssueBuilder.default_project_id }
    @target_project = chosen || from_hook || default_project || @available_projects.first
    return deny_access unless @target_project

    @trackers = Issue.allowed_target_trackers(@target_project, User.current).to_a
    @default_tracker = @trackers.detect { |t| t.id == RedmineQboBilling::EstimateIssueBuilder.default_tracker_id } || @trackers.first
    @templates = RedmineQboBilling::IssueTemplateSupport.templates_for(@target_project)
    @field_set = RedmineQboBilling::IssueFieldSet.new(project: @target_project, trackers: @trackers)
    @rows ||= {}
  rescue *QBO_ERRORS => e
    flash[:error] = qbo_message(e)
    redirect_back_or_default home_path
  end

  # The first non-empty hash a plugin returns for :qbo_billing_issue_defaults
  def issue_defaults
    results = Redmine::Hook.call_hook(:qbo_billing_issue_defaults, { estimate: @estimate, params: params })
    (results.detect { |r| r.is_a?(Hash) && r.any? } || {}).symbolize_keys
  end

  # Plugins' own fields on the preview form (issue_plugin_fields[...], drawn by :view_qbo_estimate_issues_form),
  # only when the form was posted: { vehicle_id: "5" }
  def submitted_plugin_fields
    return {} unless request.post?

    values = params[:issue_plugin_fields]
    values.respond_to?(:to_unsafe_h) ? values.to_unsafe_h.to_h.transform_keys(&:to_sym).transform_values(&:to_s) : {}
  end

  # The shared custom field values from the preview form: { custom_field_id => value }
  def submitted_custom_field_values
    values = params.dig(:issue, :custom_field_values)
    values.respond_to?(:to_unsafe_h) ? values.to_unsafe_h : {}
  end

  def estimate_params
    params.require(:estimate).permit(
      :sync_token, :total_tax, :discount, :email_status, :txn_status,
      *RedmineQboBilling::EstimateForm::HEADER_ATTRIBUTES,
      custom_fields: {},
      lines: RedmineQboBilling::EstimateForm::Line::PARAMS
    )
  end

  def save_and_send?
    params[:save_and_send].present?
  end

  def require_sender_for_save_and_send
    deny_access if save_and_send? && !RedmineQboBilling.sender?
  end

  # After saving: email it if asked, then reopen the saved estimate
  def finish_save(saved, notice)
    if save_and_send?
      begin
        sent = RedmineQboBilling::EstimateWriter.send_email(saved.id, @form.email)
        notice = l(:notice_estimate_saved_and_sent, number: sent.doc_number, email: sent.bill_email&.address || @form.email)
      rescue *QBO_ERRORS => e
        flash[:error] = l(:error_estimate_saved_not_sent, message: qbo_message(e))
      end
    end
    flash[:notice] = notice
    redirect_to edit_qbo_estimate_path(saved.id)
  end

  def show_error(error, view)
    logger.warn "[RedmineQboBilling] #{error.class}: #{qbo_message(error)}"
    @form.errors.add(:base, qbo_message(error))
    show_invalid(view)
  end

  # Shows the form again with what was typed. Empty rows are dropped so the line numbers in the
  # error messages match the table, and the billing address (display only) is looked up again.
  def show_invalid(view)
    @form.lines = @form.filled_lines
    customer = Customer.find_by(id: @form.customer_id) if @form.customer_id.present?
    @form.billing_address = RedmineQboBilling::EstimateWriter.customer_address(customer) if customer
    render view, status: :unprocessable_entity
  end

  # QuickBooks errors carry their detail separately from the message
  def qbo_message(error)
    detail = error.respond_to?(:detail) ? error.detail.to_s : ''
    message = error.message.to_s
    detail.present? && !message.include?(detail) ? "#{message}: #{detail}" : message
  end
end

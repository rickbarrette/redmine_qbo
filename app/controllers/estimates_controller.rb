#The MIT License (MIT)
#
#Copyright (c) 2016 - 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
class EstimatesController < ApplicationController
  include AuthHelper

  # PDFs: logged-in users, or a customer with a share link (limited to their issue's estimate).
  # Redmine's own login check is replaced by require_login_or_customer_token for these actions.
  skip_before_action :check_if_login_required, only: [:show, :doc]
  before_action :require_login_or_customer_token, only: [:show, :doc]
  before_action :load_estimate, only: [:show, :doc]

  # Syncing is admin-only
  before_action :require_admin, only: :sync
  
  # Displays the estimate PDF in the browser or redirects with an error if not found.
  def doc
    render_pdf(@estimate)
  end

  # Displays the estimate PDF in the browser or redirects with an error if not found.
  def show
    render_pdf(@estimate)
  end

  def sync
    Estimate.sync
    redirect_back fallback_location: home_path, flash: { notice: I18n.t(:label_syncing) }
  end

  private

  # Loads the estimate based on ID or doc number, with a fallback to sync if not found locally.
  def load_estimate
    log "Attempting to load Estimate with params: #{params.inspect}"

    # Share-link customers may only open the estimate attached to their issue (checked before any sync)
    return load_customer_estimate if customer_token_only?

    @estimate = find_estimate || sync_and_find_estimate

    unless @estimate
      redirect_back fallback_location: root_path, flash: { error: I18n.t(:notice_estimate_not_found) }
    end
  end

  # For share-link customers: only the estimate attached to the token's issue, by ID or doc number.
  def load_customer_estimate
    estimate = customer_token.issue&.estimate
    requested =
      if params[:search].present?
        estimate && estimate.doc_number.to_s == params[:search].to_s
      else
        estimate && estimate.id.to_s == params[:id].to_s
      end

    return render_403 unless requested

    @estimate = estimate
  end

  # Attempts to find the estimate locally by ID or doc number.
  def find_estimate
    return Estimate.find_by(doc_number: params[:search]) if params[:search].present?
    return Estimate.find_by(id: params[:id]) if params[:id].present?
  end

  # If the estimate is not found locally, attempts to sync it from the source and find it again.
  def sync_and_find_estimate

    if params[:search].present?
      log "Estimate #{params[:search]} not found locally. Syncing by doc number."
      Estimate.sync_by_doc_number(params[:search])
      return Estimate.find_by(doc_number: params[:search])
    end

    if params[:id].present?
      log "Estimate #{params[:id]} not found locally. Syncing by ID."
      Estimate.sync_by_id(params[:id])
      return Estimate.find_by(id: params[:id])
    end

    nil
  rescue StandardError => e
    log "Estimate sync failed: #{e.message}"
    nil
  end

  # Renders the estimate PDF or redirects with an error if rendering fails.
  def render_pdf(estimate)
    pdf, ref = PdfService.new(entity: Estimate).fetch_pdf(doc_ids: [estimate.id])
    send_data( pdf, filename: "estimate #{ref}.pdf", disposition: :inline, type: "application/pdf" )
  rescue StandardError => e
    log "PDF render failed for Estimate #{estimate&.id}: #{e.message}"
    redirect_back fallback_location: root_path, flash: { error: I18n.t(:notice_estimate_not_found) }
  end

  # Logs messages with a consistent prefix for easier debugging.
  def log(msg)
    Rails.logger.info "[EstimateController] #{msg}"
  end
end
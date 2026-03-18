#The MIT License (MIT)
#
#Copyright (c) 2016 - 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
class EstimateController < ApplicationController
  include AuthHelper

  before_action :require_user, unless: -> { session[:token].nil? }
  skip_before_action :verify_authenticity_token, :check_if_login_required, unless: -> { session[:token].nil? }
  before_action :load_estimate, only: [:show, :doc]
  
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
    redirect_to :home, flash: { notice: I18n.t(:label_syncing) }
  end

  private

  # Loads the estimate based on ID or doc number, with a fallback to sync if not found locally.
  def load_estimate
    log "Attempting to load Estimate with params: #{params.inspect}"
    @estimate = find_estimate || sync_and_find_estimate

    unless @estimate
      redirect_back fallback_location: root_path, flash: { error: I18n.t(:notice_estimate_not_found) }
    end
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
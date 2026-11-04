#The MIT License (MIT)
#
#Copyright (c) 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

# Estimate and invoice drafts (QboDraft): all of them, and deleting one. Drafts are continued on the new
# estimate/invoice editor (new?draft_id=). Users see the drafts of the documents they may write.
class QboDraftsController < ApplicationController

  before_action :authorize_global

  def index
    @drafts = QboDraft.visible.includes(:customer, :user).newest_first.to_a
  end

  def destroy
    draft = QboDraft.visible.find_by(id: params[:id])
    if draft
      draft.destroy
      flash[:notice] = l(:notice_qbo_draft_deleted)
    else
      flash[:error] = l(:error_qbo_draft_not_found)
    end
    redirect_back_or_default qbo_drafts_path
  end
end

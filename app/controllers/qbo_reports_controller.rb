#The MIT License (MIT)
#
#Copyright (c) 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.


# Business report: estimates and invoices written and payments received, and estimated, invoiced and spent
# hours, for a period (RedmineQboBilling::BusinessReport)
class QboReportsController < ApplicationController

  before_action :authorize_global

  # The user's preference holding the projects the report opens with
  PROJECTS_PREF = :qbo_report_project_ids

  def index
    # Projects for the issues and spent time: the projects picker can choose some of the open ones
    @projects = Project.visible.active.to_a
    @project_ids = report_project_ids
    @report = RedmineQboBilling::BusinessReport.new(period: params[:period].presence || 'this_year',
                                                    from: params[:from], to: params[:to], today: User.current.today,
                                                    week_start: RedmineQboBilling::BusinessReport.week_start_from_setting(Setting.start_of_week),
                                                    project_ids: @project_ids)
    # Last year's lines on the charts
    @compare = params[:compare] == '1'
    # Syncs still running for what the report counts: its figures are incomplete until they finish
    @syncing = QboSyncStatus.by_entity(%w[Estimate Invoice Payment]).values.sort_by(&:entity)
  end

  private

  # The form's projects (none picked is every project), or the user's saved ones when the address has none.
  # "Remember these projects" saves the form's choice. Only open projects the user can see are kept.
  def report_project_ids
    visible = @projects.map(&:id)
    if params.key?(:project_ids)
      ids = Array(params[:project_ids]).map(&:to_i) & visible
      save_project_ids(ids) if params[:save_projects] == '1'
    else
      ids = saved_project_ids & visible
    end
    @saved_project_ids = saved_project_ids & visible
    ids
  end

  def saved_project_ids
    return [] unless User.current.logged?
    Array(User.current.pref[PROJECTS_PREF]).map(&:to_i)
  end

  def save_project_ids(ids)
    return unless User.current.logged?
    pref = User.current.pref
    pref[PROJECTS_PREF] = ids
    pref.save
  end
end

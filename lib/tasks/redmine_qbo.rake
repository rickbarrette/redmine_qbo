#The MIT License (MIT)
#
#Copyright (c) 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

namespace :redmine_qbo do
  desc 'Relate all issues created from the same QBO estimate to each other (one-time catch-up; safe to re-run)'
  task relate_estimate_issues: :environment do
    total = 0
    estimates = QboEstimateLineIssue.distinct.pluck(:estimate_id)

    estimates.each do |estimate_id|
      issues = QboEstimateLineIssue.where(estimate_id: estimate_id).includes(:issue).filter_map(&:issue)
      total += RedmineQboBilling::EstimateIssueBuilder.relate_all(issues)
    end

    puts "Checked #{estimates.size} estimate(s), created #{total} relation(s)."
  end
end

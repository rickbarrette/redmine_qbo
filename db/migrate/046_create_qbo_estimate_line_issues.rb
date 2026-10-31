#The MIT License (MIT)
#
#Copyright (c) 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

# Records which issue was created from which QuickBooks estimate line, so a line can't be turned into an
# issue twice. Issues redmine_qbo_calendar created from appointment estimates are copied in, so they still
# count as created.
class CreateQboEstimateLineIssues < ActiveRecord::Migration[7.0]
  class LineIssue < ActiveRecord::Base
    self.table_name = 'qbo_estimate_line_issues'
  end

  def up
    unless table_exists?(:qbo_estimate_line_issues)
      create_table :qbo_estimate_line_issues do |t|
        t.bigint :estimate_id, null: false
        t.string :line_id, null: false
        t.references :issue, null: false, index: { unique: true }
        t.datetime :created_on, null: false
      end
      add_index :qbo_estimate_line_issues, [:estimate_id, :line_id], unique: true, name: 'index_qbo_estimate_line_issues_on_line'
    end

    return unless table_exists?(:appointment_estimate_issues)

    LineIssue.reset_column_information
    existing_issue_ids = select_values('SELECT id FROM issues').map(&:to_i).to_set
    select_all('SELECT estimate_id, line_id, issue_id, created_on FROM appointment_estimate_issues').each do |row|
      next unless existing_issue_ids.include?(row['issue_id'].to_i)
      next if LineIssue.exists?(estimate_id: row['estimate_id'], line_id: row['line_id']) || LineIssue.exists?(issue_id: row['issue_id'])

      LineIssue.create!(estimate_id: row['estimate_id'], line_id: row['line_id'], issue_id: row['issue_id'],
                        created_on: row['created_on'] || Time.current)
    end
  end

  def down
    drop_table :qbo_estimate_line_issues if table_exists?(:qbo_estimate_line_issues)
  end
end

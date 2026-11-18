#The MIT License (MIT)
#
#Copyright (c) 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

require File.expand_path('../test_helper', __dir__)

class CustomerTokenTest < ActiveSupport::TestCase
  fixtures :projects, :users, :email_addresses, :members, :member_roles, :roles, :issues, :trackers,
           :projects_trackers, :issue_statuses, :enabled_modules, :enumerations

  def setup
    CustomerToken.delete_all
    User.current = User.find(1)
  end

  def token(issue_id, expires_at)
    CustomerToken.create!(issue_id: issue_id, expires_at: expires_at)
  end

  def test_purge_expired
    active = token(1, 1.week.from_now)
    token(2, 1.day.ago)
    token(3, 1.month.ago)
    token(99_999, 1.week.from_now) # its issue was deleted
    assert_equal 3, CustomerToken.purge_expired
    assert_equal [active.id], CustomerToken.pluck(:id)
  end

  def test_a_new_share_link_clears_out_old_ones
    token(2, 1.day.ago)
    link = CustomerToken.get_token(Issue.find(1))
    assert link.expires_at > Time.current
    assert_equal [link.id], CustomerToken.pluck(:id)
  end

  def test_an_active_link_is_reused
    active = token(1, 1.week.from_now)
    token(2, 1.day.ago)
    assert_equal active, CustomerToken.get_token(Issue.find(1))
    assert_equal 2, CustomerToken.count # nothing new made, nothing cleared
  end
end

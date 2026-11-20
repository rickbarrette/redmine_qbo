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

# Estimates linked to an issue are read-only unless unlocked by a user with "Edit estimates linked to issues"
class LinkedEstimateUnlockTest < ActiveSupport::TestCase
  Writer = RedmineQboBilling::EstimateWriter

  def user(*permissions)
    user = User.new
    user.stubs(:allowed_to?).returns(false)
    permissions.each { |p| user.stubs(:allowed_to?).with(p, nil, global: true).returns(true) }
    user
  end

  def form(linked:)
    Writer.stubs(:linked_issues).with('701').returns(stub(exists?: linked))
    RedmineQboBilling::EstimateForm.new.tap { |f| f.id = '701' }
  end

  def test_editor_needs_write_estimates_and_edit_linked_estimates
    assert RedmineQboBilling.linked_estimate_editor?(user(:write_estimates, :edit_linked_estimates))
    assert_not RedmineQboBilling.linked_estimate_editor?(user(:write_estimates))
    assert_not RedmineQboBilling.linked_estimate_editor?(user(:edit_linked_estimates))
  end

  def test_unlinked_estimate_saves_without_unlocking
    assert_nothing_raised { Writer.check_linked(form(linked: false), false, user(:write_estimates)) }
  end

  def test_linked_estimate_is_locked_without_unlock
    error = assert_raises(Writer::Error) do
      Writer.check_linked(form(linked: true), false, user(:write_estimates, :edit_linked_estimates))
    end
    assert_equal I18n.t(:error_estimate_linked_to_issues), error.message
  end

  def test_unlock_needs_the_permission
    error = assert_raises(Writer::Error) { Writer.check_linked(form(linked: true), true, user(:write_estimates)) }
    assert_equal I18n.t(:error_estimate_linked_not_allowed), error.message
  end

  def test_unlocked_by_an_editor_saves
    assert_nothing_raised do
      Writer.check_linked(form(linked: true), true, user(:write_estimates, :edit_linked_estimates))
    end
  end
end

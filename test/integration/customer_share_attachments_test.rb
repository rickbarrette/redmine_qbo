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

# Files on an issue shared through a customer link (customers/view/:token) open for the anonymous
# visitor holding the link, and nothing else does.
class CustomerShareAttachmentsTest < Redmine::IntegrationTest
  fixtures :projects, :users, :email_addresses, :members, :member_roles, :roles, :issues, :trackers,
           :projects_trackers, :issue_statuses, :enabled_modules, :enumerations, :attachments, :journals

  # Issue 4 is in a private project; attachment 7 is on it, attachment 1 is on issue 3.
  def setup
    set_fixtures_attachments_directory
    CustomerToken.delete_all
    User.current = User.find(1)
    @token = CustomerToken.create!(issue_id: 4, expires_at: 1.week.from_now)
    User.current = nil
  end

  def teardown
    set_tmp_attachments_directory
  end

  def open_share_link
    get "/customers/view/#{@token.token}"
    assert_response :success
  end

  def test_without_the_link_files_need_a_login
    with_settings login_required: '1' do
      get '/attachments/download/7/archive.zip'
      assert_redirected_to %r{/login}
    end
  end

  def test_share_link_opens_the_issues_files
    with_settings login_required: '1' do
      open_share_link
      assert_select 'a[href=?]', '/attachments/7'

      get '/attachments/7'
      assert_response :success
      get '/attachments/download/7/archive.zip'
      assert_response :success
      assert_equal 'application/zip', response.media_type
      get '/attachments/issues/4/download'
      assert_response :success
    end
  end

  def test_share_link_does_not_open_other_files
    with_settings login_required: '1' do
      open_share_link
      get '/attachments/download/1/error281.txt'
      assert_redirected_to %r{/login}
      get '/attachments/issues/3/download'
      assert_redirected_to %r{/login}
    end
  end

  def test_files_on_private_notes_stay_hidden
    journal = Journal.create!(journalized: Issue.find(4), user: User.find(1), notes: 'internal', private_notes: true)
    Attachment.find(1).update_columns(container_type: 'Journal', container_id: journal.id)
    with_settings login_required: '1' do
      open_share_link
      get '/attachments/download/1/error281.txt'
      assert_redirected_to %r{/login}
    end
  end

  def test_expired_link_opens_nothing
    with_settings login_required: '1' do
      open_share_link
      @token.update_columns(expires_at: 1.minute.ago)
      get '/attachments/download/7/archive.zip'
      assert_redirected_to %r{/login}
    end
  end
end

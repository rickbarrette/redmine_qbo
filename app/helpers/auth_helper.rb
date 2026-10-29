#The MIT License (MIT)
#
#Copyright (c) 2016 - 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

module AuthHelper

  # The active customer share token stored in the session by customers#view, if any.
  def customer_token
    return @customer_token if defined?(@customer_token)

    @customer_token = session[:token].present? ? CustomerToken.active.find_by(token: session[:token]) : nil
  end

  # True when the visitor is a customer using a share link rather than a logged-in user.
  def customer_token_only?
    !User.current.logged? && customer_token.present?
  end

  # Logged-in users pass. Customers with an active share link pass too (each controller then limits them
  # to their own issue's documents). Everyone else is sent to the login page.
  def require_login_or_customer_token
    return true if User.current.logged?
    return true if customer_token

    require_login
  end

  # Kept for plugins that still call it (e.g. redmine_qbo_vehicles): requires a logged-in user.
  # The old version effectively never ran; share-link customers use require_login_or_customer_token.
  def require_user
    return true if User.current.logged?

    require_login
  end

  def allowed_to?(action)
    return false if User.current.nil?
    project = Project.find_by(id: params[:project_id])
    return false if project.nil?
    User.current.allowed_to?(action, project)
  end

  def check_permission(permission)
    if !allowed_to?(permission)
      flash[:error] = t :notice_forbidden
      render_403
    end
  end

  def global_check_permission(permission)
    if !globaly_allowed_to?(permission)
      flash[:error] = t :notice_forbidden
      render_403
    end
  end

  # True if the user has the permission through any of their roles (or is an admin)
  def globaly_allowed_to?(action)
    return false if User.current.nil?

    User.current.allowed_to?(action, nil, global: true)
  end

end

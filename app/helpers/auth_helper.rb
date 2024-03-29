#The MIT License (MIT)
#
#Copyright (c) 2017 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

module AuthHelper

  def require_user
    return unless session[:token].nil?
    if !User.current.logged?
      render_403
    end
  end
  
  def allowed_to?(action)
    return false if User.current.nil?
    project = Project.find(params[:project_id])
    return false if project.nil?
    return true if User.current.allowed_to?(action, project)
    false
  end
  
  def check_permission(permission)
    if !allowed_to?(permission)
      render_403
    end
  end
  
  
  def global_check_permission(permission)
    if !globaly_allowed_to?(permission)
      render_403
    end
  end
  
  def globaly_allowed_to?( action)
    return false if User.current.nil?

    projects = Project.all
    projects.each { |p|
      if User.current.allowed_to?(action, p)
        return true
      end
    }
    false
  end
    
end

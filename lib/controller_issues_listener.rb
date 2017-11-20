class ControllerIssuesListener.rb < Redmine::Hook::ControllerListener
  def controller_issues_new_before_save(context={})
    context[:issue].project = Project.find_by identifier: context[:params][:project]
  end
end

class ViewHookListener < Redmine::Hook::ViewListener
  render_on :view_issues_sidebar_issues_bottom, :partial => "customers/sidebar"
end

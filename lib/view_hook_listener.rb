class ViewHookListener < Redmine::Hook::ViewListener
  render_on :view_layouts_base_sidebar, :partial => "qbo/sidebar"
end

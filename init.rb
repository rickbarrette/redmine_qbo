Redmine::Plugin.register :redmine_qbo do

 require_dependency 'qbo_hook_listener'

  name 'Redmine Quickbooks Online plugin'
  author 'Rick Barrette'
  description 'This is a plugin for Redmine to intergrate with Quickbooks Online to allow for seamless intergration CRM and invoicing of completed issues'
  version '0.0.1'
  url 'http://example.com/path/to/plugin'
  author_url 'http://rickbarrette.org'
  settings :default => {'empty' => true}, :partial => 'qbo/settings'


  Quickbooks.sandbox_mode = true
end

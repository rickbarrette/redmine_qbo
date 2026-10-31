#The MIT License (MIT)
#
#Copyright (c) 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

module RedmineQboBilling
  # Optional support for redmine_issue_templates (https://github.com/agileware-jp/redmine_issue_templates).
  # Everything here returns empty results when that plugin isn't installed or isn't enabled on the project.
  module IssueTemplateSupport
    Option = Struct.new(:key, :title, :tracker_id, :is_default, :description, :group, keyword_init: true)

    module_function

    def installed?
      defined?(::IssueTemplate) && defined?(::GlobalIssueTemplate) && defined?(::IssueTemplateSetting)
    end

    def enabled_for?(project)
      !!(installed? && project&.module_enabled?(:issue_templates))
    end

    # Templates usable in the project: its own, those shared by parent projects, and global ones.
    def templates_for(project)
      return [] unless enabled_for?(project)

      own = ::IssueTemplate.get_templates_for_project_tracker(project.id).to_a
      inherited = Array(::IssueTemplateSetting.find_or_create(project.id).get_inherit_templates).to_a
      global = ::GlobalIssueTemplate.get_templates_for_project_tracker(project.id).to_a

      (own + inherited).uniq.map { |t| option('project', t) } + global.map { |t| option('global', t) }
    rescue StandardError => e
      Rails.logger.warn "[IssueTemplateSupport] Could not load templates: #{e.class}: #{e.message}"
      []
    end

    def find(key, project)
      return nil if key.blank?

      templates_for(project).detect { |t| t.key == key }
    end

    def option(group, template)
      Option.new(
        key: "#{group}:#{template.id}",
        title: template.title,
        tracker_id: template.tracker_id,
        is_default: template.is_default?,
        description: template.description,
        group: group
      )
    end
  end
end

#The MIT License (MIT)
#
#Copyright (c) 2016 - 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

module RedmineQbo
  module Patches
    module PdfPatch
      extend ActiveSupport::Concern

      def issue_to_pdf(issue, assoc={})
        pdf = setup_pdf(issue)

        render_header(pdf, issue)
        render_ancestors_and_subject(pdf, issue)
        
        left, right = build_issue_attributes(issue)
        render_attributes_grid(pdf, left, right)

        render_description(pdf, issue)
        render_subtasks(pdf, issue)
        render_relations(pdf, issue)
        render_changesets(pdf, issue)
        render_journals(pdf, issue, assoc)
        render_attachments(pdf, issue)

        merge_estimate_if_present(pdf, issue)
      end

      private

      def log(msg)
        Rails.logger.info "[PdfPatch] #{msg}"
      end

      def setup_pdf(issue)
        pdf = ::Redmine::Export::PDF::ITCPDF.new(current_language)
        pdf.set_title("#{issue.project} - #{issue.tracker} ##{issue.id}")
        pdf.alias_nb_pages
        pdf.footer_date = format_date(Date.today)
        pdf.add_page
        pdf
      end

      def render_header(pdf, issue)
        pdf.SetFontStyle('B', 11)
        pdf.RDMMultiCell(190, 5, "#{issue.project} - #{issue.tracker} ##{issue.id}")
        pdf.SetFontStyle('', 8)
      end

      def render_ancestors_and_subject(pdf, issue)
        base_x = pdf.get_x
        i = 1
        
        # Render ancestors
        issue.ancestors.visible.each do |ancestor|
          pdf.set_x(base_x + i)
          buf = "#{ancestor.tracker} # #{ancestor.id} (#{ancestor.status}): #{ancestor.subject}"
          pdf.RDMMultiCell(190 - i, 5, buf)
          i += 1 if i < 35
        end

        # Render current issue subject and meta
        pdf.SetFontStyle('B', 11)
        pdf.RDMMultiCell(190 - i, 5, issue.subject.to_s)
        pdf.SetFontStyle('', 8)
        pdf.RDMMultiCell(190, 5, "#{format_time(issue.created_on)} - #{issue.author}")
        pdf.ln
      end

      def build_issue_attributes(issue)
        left = build_left_attributes(issue)
        right = build_right_attributes(issue)

        # Pad arrays to equal length
        rows = [left.size, right.size].max
        left.fill(nil, left.size...rows)
        right.fill(nil, right.size...rows)

        # Distribute custom fields evenly
        half = (issue.visible_custom_field_values.size / 2.0).ceil
        issue.visible_custom_field_values.each_with_index do |custom_value, i|
          target_column = i < half ? left : right
          target_column << [custom_value.custom_field.name, show_value(custom_value, false)]
        end

        [left, right]
      end

      def build_left_attributes(issue)
        left = []
        left << [l(:field_status), issue.status]
        left << [l(:field_priority), issue.priority]
        left << [l(:field_customer), issue.customer&.name]
        left << [l(:field_assigned_to), issue.assigned_to] unless issue.disabled_core_fields.include?(:assigned_to_id)

        log "Calling :pdf_left hook"
        left_hook_output = Redmine::Hook.call_hook(:pdf_left, { issue: issue })
        Array(left_hook_output).compact.each { |l| left.concat(l) }
        
        left
      end

      def build_right_attributes(issue)
        right = []
        right << [l(:field_start_date), format_date(issue.start_date)] unless issue.disabled_core_fields.include?(:start_date)
        right << [l(:field_due_date), format_date(issue.due_date)] unless issue.disabled_core_fields.include?(:due_date)
        right << [l(:field_done_ratio), "#{issue.done_ratio}%"] unless issue.disabled_core_fields.include?(:done_ratio)
        right << [l(:field_estimated_hours), l_hours(issue.estimated_hours)] unless issue.disabled_core_fields.include?(:estimated_hours)
        right << [l(:label_spent_time), l_hours(issue.total_spent_hours)] if User.current.allowed_to?(:view_time_entries, issue.project)

        log "Calling :pdf_right hook"
        right_hook_output = Redmine::Hook.call_hook(:pdf_right, { issue: issue })
        Array(right_hook_output).compact.each { |r| right.concat(r) }
        
        right
      end

      def render_attributes_grid(pdf, left, right)
        base_x = pdf.get_x
        borders = determine_borders(pdf.get_rtl)
        rows = [left.size, right.size].max

        rows.times do |i|
          item_left = left[i]
          item_right = right[i]

          # Calculate dynamic row height
          pdf.SetFontStyle('B', 9)
          hl1 = pdf.get_string_height(35, item_left ? "#{item_left.first}:" : "")
          hr1 = pdf.get_string_height(35, item_right ? "#{item_right.first}:" : "")
          
          pdf.SetFontStyle('', 9)
          hl2 = pdf.get_string_height(60, item_left ? item_left.last.to_s : "")
          hr2 = pdf.get_string_height(60, item_right ? item_right.last.to_s : "")
          
          height = [hl1, hr1, hl2, hr2].max

          # Render cells
          render_grid_cell(pdf, item_left, height, i == 0 ? borders[:first_top] : borders[:first], i == 0 ? borders[:last_top] : borders[:last], 0)
          render_grid_cell(pdf, item_right, height, i == 0 ? borders[:first_top] : borders[:first], i == 0 ? borders[:last_top] : borders[:last], 2)

          pdf.set_x(base_x)
        end
      end

      def determine_borders(is_rtl)
        if is_rtl
          { first_top: 'RT', last_top: 'LT', first: 'R', last: 'L' }
        else
          { first_top: 'LT', last_top: 'RT', first: 'L', last: 'R' }
        end
      end

      def render_grid_cell(pdf, item, height, border_label, border_val, ln_type)
        pdf.SetFontStyle('B', 9)
        pdf.RDMMultiCell(35, height, item ? "#{item.first}:" : "", border_label, '', 0, 0)
        
        pdf.SetFontStyle('', 9)
        pdf.RDMMultiCell(60, height, item ? item.last.to_s : "", border_val, '', 0, ln_type)
      end

      def render_description(pdf, issue)
        pdf.SetFontStyle('B', 9)
        pdf.RDMCell(190, 5, l(:field_description), "LRT", 1)
        pdf.SetFontStyle('', 9)

        pdf.set_image_scale(1.6)
        text = textilizable(issue, :description,
                            only_path: false,
                            edit_section_links: false,
                            headings: false,
                            inline_attachments: false)
        pdf.RDMwriteFormattedCell(190, 5, '', '', text, issue.attachments, "LRB")
      end

      def render_subtasks(pdf, issue)
        return if issue.leaf?

        truncate_length = !is_cjk? ? 90 : 65
        pdf.SetFontStyle('B', 9)
        pdf.RDMCell(190, 5, "#{l(:label_subtask_plural)}:", "LTR")
        pdf.ln

        border_first = pdf.get_rtl ? 'R' : 'L'
        border_last = pdf.get_rtl ? 'L' : 'R'

        issue_list(issue.descendants.visible.sort_by(&:lft)) do |child, level|
          buf = "#{child.tracker} # #{child.id}: #{child.subject}".truncate(truncate_length)
          level = 10 if level >= 10
          
          pdf.SetFontStyle('', 8)
          pdf.RDMCell(170, 5, (level >= 1 ? "  " * level : "") + buf, border_first)
          pdf.SetFontStyle('B', 8)
          pdf.RDMCell(20, 5, child.status.to_s, border_last)
          pdf.ln
        end
      end

      def render_relations(pdf, issue)
        relations = issue.relations.select { |r| r.other_issue(issue).visible? }
        return if relations.empty?

        truncate_length = !is_cjk? ? 80 : 60
        pdf.SetFontStyle('B', 9)
        pdf.RDMCell(190, 5, "#{l(:label_related_issues)}:", "LTR")
        pdf.ln

        border_first = pdf.get_rtl ? 'R' : 'L'
        border_last = pdf.get_rtl ? 'L' : 'R'

        relations.each do |relation|
          other = relation.other_issue(issue)
          text = Setting.cross_project_issue_relations? ? "#{other.project} - " : ""
          text += "#{other.tracker} ##{other.id}: #{other.subject}"

          pdf.SetFontStyle('', 8)
          pdf.RDMCell(130, 5, text.truncate(truncate_length), border_first)
          pdf.SetFontStyle('B', 8)
          pdf.RDMCell(20, 5, other.status.to_s, "")
          pdf.RDMCell(20, 5, format_date(other.start_date), "")
          pdf.RDMCell(20, 5, format_date(other.due_date), border_last)
          pdf.ln
        end
        pdf.RDMCell(190, 5, "", "T")
        pdf.ln
      end

      def render_changesets(pdf, issue)
        return unless issue.changesets.any? && User.current.allowed_to?(:view_changesets, issue.project)

        pdf.SetFontStyle('B', 9)
        pdf.RDMCell(190, 5, l(:label_associated_revisions), "B")
        pdf.ln
        
        issue.changesets.each do |changeset|
          pdf.SetFontStyle('B', 8)
          csstr = "#{l(:label_revision)} #{changeset.format_identifier} - #{format_time(changeset.committed_on)} - #{changeset.author}"
          pdf.RDMCell(190, 5, csstr)
          pdf.ln
          
          unless changeset.comments.blank?
            pdf.SetFontStyle('', 8)
            pdf.RDMwriteHTMLCell(190, 5, '', '', changeset.comments.to_s, issue.attachments, "")
          end
          pdf.ln
        end
      end

      def render_journals(pdf, issue, assoc)
        return unless assoc[:journals].present?

        pdf.SetFontStyle('B', 9)
        pdf.RDMCell(190, 5, l(:label_history), "B")
        pdf.ln
        
        assoc[:journals].each do |journal|
          pdf.SetFontStyle('B', 8)
          title = "##{journal.indice} - #{format_time(journal.created_on)} - #{journal.user}"
          title << " (#{l(:field_private_notes)})" if journal.private_notes?
          pdf.RDMCell(190, 5, title)
          pdf.ln
          
          pdf.SetFontStyle('I', 8)
          details_to_strings(journal.visible_details, true).each do |string|
            pdf.RDMMultiCell(190, 5, "- " + string)
          end
          
          if journal.notes?
            pdf.ln unless journal.details.empty?
            pdf.SetFontStyle('', 8)
            text = textilizable(journal, :notes, only_path: false, edit_section_links: false, headings: false, inline_attachments: false)
            pdf.RDMwriteFormattedCell(190, 5, '', '', text, issue.attachments, "")
          end
          pdf.ln
        end
      end

      def render_attachments(pdf, issue)
        return unless issue.attachments.any?

        pdf.SetFontStyle('B', 9)
        pdf.RDMCell(190, 5, l(:label_attachment_plural), "B")
        pdf.ln
        
        issue.attachments.each do |attachment|
          pdf.SetFontStyle('', 8)
          pdf.RDMCell(80, 5, attachment.filename)
          pdf.RDMCell(20, 5, number_to_human_size(attachment.filesize), 0, 0, "R")
          pdf.RDMCell(25, 5, format_date(attachment.created_on), 0, 0, "R")
          pdf.RDMCell(65, 5, attachment.author.name, 0, 0, "R")
          pdf.ln
        end
      end

      def merge_estimate_if_present(pdf, issue)
        if issue.estimate
          e_pdf, _ref = PdfService.new(entity: Estimate).fetch_pdf(doc_ids: [issue.estimate.id])
          combined = CombinePDF.parse(pdf.output, allow_optional_content: true)
          combined << CombinePDF.parse(e_pdf)
          combined.to_pdf
        else
          pdf.output
        end
      end

    end
  end
end
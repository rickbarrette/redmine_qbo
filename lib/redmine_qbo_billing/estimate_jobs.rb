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
  # Groups an estimate's lines into jobs: each labor line with the parts and notes that go with it, for
  # the issues created from the estimate.
  #
  # - A subtotal line ends a job (so does the end of the estimate)
  # - A part or note belongs to the labor line before it; parts before the first labor line of a job
  #   belong to that first labor line (estimates written parts first, then labor)
  # - Notes (description-only lines) before the first item are the estimate's own (e.g. the diagnosis)
  #   and go with every job
  # - Parts in a job without a labor line (e.g. tires and wheels) belong to no issue
  #
  # Parts first with no subtotal between two jobs can't be told apart (the second job's parts follow the
  # first labor line); #ambiguous? says when that may have happened.
  class EstimateJobs
    Part = Struct.new(:quantity, :item_name, :description, keyword_init: true)
    Job = Struct.new(:line_id, :parts, :notes, keyword_init: true)

    # QBO line Ids are stable for the life of the estimate; fall back to line number / position
    def self.line_key(line, index)
      key = line.respond_to?(:id) ? line.id : nil
      key = line.line_num if key.blank? && line.respond_to?(:line_num)
      key = "pos-#{index}" if key.blank?
      key.to_s
    end

    attr_reader :notes

    # labor: ->(item_ref) { true when the line's product/service is labor }
    def initialize(line_items, labor: ->(item_ref) { LaborItems.match?(item_ref) })
      @labor = labor
      @jobs = {}
      @notes = []
      @ambiguous = false
      group(Array(line_items))
    end

    def job(line_id)
      @jobs[line_id.to_s]
    end

    def ambiguous?
      @ambiguous
    end

    private

    def group(lines)
      started = false
      reset_job

      lines.each_with_index do |line, index|
        case kind(line)
        when :subtotal
          reset_job
        when :note
          text = line.description.to_s.strip
          next if text.empty?

          started ? add(:notes, text) : @notes << text
        when :labor
          started = true
          labor_line(self.class.line_key(line, index))
        when :part
          started = true
          add(:parts, part(line))
        end
      end
    end

    def kind(line)
      type = line.respond_to?(:detail_type) ? line.detail_type.to_s : ''
      return :subtotal if type == 'SubTotalLineDetail'
      return :note if type == 'DescriptionOnly'
      return :part if type == 'GroupLineDetail'

      detail = line.respond_to?(:sales_line_item_detail) ? line.sales_line_item_detail : nil
      return :ignore if detail.nil? || detail.item_ref.nil?

      @labor.call(detail.item_ref) ? :labor : :part
    end

    def reset_job
      @current = nil
      @labor_count = 0
      @pending = { parts: [], notes: [] }
    end

    def labor_line(line_id)
      job = Job.new(line_id: line_id, parts: [], notes: [])
      @labor_count += 1
      if @current.nil?
        job.parts.concat(@pending[:parts])
        job.notes.concat(@pending[:notes])
      elsif @pending[:parts].any?
        # Parts came first, then a second labor line with no subtotal in between
        @ambiguous = true
      end
      @current = job
      @jobs[line_id] = job
    end

    def add(kind, item)
      if @current
        @current.send(kind) << item
      else
        @pending[kind] << item
      end
    end

    def part(line)
      if line.respond_to?(:detail_type) && line.detail_type.to_s == 'GroupLineDetail'
        detail = line.group_line_detail
        return Part.new(quantity: quantity(detail&.quantity), item_name: detail&.group_item_ref&.name.to_s,
                        description: line.description.to_s.strip)
      end

      detail = line.sales_line_item_detail
      Part.new(quantity: quantity(detail.quantity), item_name: detail.item_ref.name.to_s.strip,
               description: line.description.to_s.strip)
    end

    def quantity(value)
      return '' if value.nil?

      number = BigDecimal(value.to_s)
      number == number.to_i ? number.to_i.to_s : number.to_s('F')
    rescue ArgumentError
      value.to_s
    end
  end
end

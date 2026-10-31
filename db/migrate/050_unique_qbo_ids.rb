#The MIT License (MIT)
#
#Copyright (c) 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.


# The customers, employees, estimates and invoices tables were created with
# `t.integer :id, options: 'PRIMARY KEY'`, which Rails ignores, so their id (the QuickBooks id) was never unique.
# Two syncs of the same record at once (e.g. saving an estimate in Redmine, then QuickBooks' webhook) could
# both insert it, and it showed twice. This keeps one row per id (the most recently updated) and adds a unique
# index so the database refuses a second one. Other tables point at these by the same id, so nothing breaks.
class UniqueQboIds < ActiveRecord::Migration[7.0]
  TABLES = %i[customers employees estimates invoices].freeze

  def up
    TABLES.each do |table|
      next unless table_exists?(table)

      remove_duplicates(table)
      add_index table, :id, unique: true, name: "index_#{table}_on_qbo_id" unless index_name_exists?(table, "index_#{table}_on_qbo_id")
    end
  end

  def down
    TABLES.each do |table|
      remove_index table, name: "index_#{table}_on_qbo_id" if table_exists?(table) && index_name_exists?(table, "index_#{table}_on_qbo_id")
    end
  end

  private

  def remove_duplicates(table)
    quoted = quote_table_name(table)
    ids = select_values("SELECT id FROM #{quoted} WHERE id IS NOT NULL GROUP BY id HAVING COUNT(*) > 1")
    say "#{table}: #{ids.size} duplicated ids" if ids.any?

    ids.each do |id|
      rows = select_all("SELECT * FROM #{quoted} WHERE id = #{quote(id)}").to_a
      keep = rows.max_by { |row| [row['updated_at'].to_s, row.values.compact.size] }
      columns = keep.keys
      values = columns.map { |c| sql_value(keep[c]) }

      # Both or neither: a failed insert must not leave the record deleted
      transaction do
        execute "DELETE FROM #{quoted} WHERE id = #{quote(id)}"
        execute "INSERT INTO #{quoted} (#{columns.map { |c| quote_column_name(c) }.join(', ')}) VALUES (#{values.join(', ')})"
      end
    end
  end

  # A value read back from the table, quoted for writing it again. Dates and times are formatted the way
  # Rails writes them (e.g. '2026-10-31 14:06:08'), not with a time zone offset, which MySQL refuses.
  def sql_value(value)
    return 'NULL' if value.nil?
    return quote(connection.quoted_date(value)) if value.is_a?(Time) || value.is_a?(Date) || value.is_a?(DateTime)

    quote(value)
  end
end

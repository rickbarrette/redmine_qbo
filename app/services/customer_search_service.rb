#The MIT License (MIT)
#
#Copyright (c) 2016 - 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

require 'csv'
require 'did_you_mean'
require 'text'

# Finds customers by name and/or phone, tolerant of the ways duplicates sneak in:
# - nicknames:    "Bill Smith" finds "William Smith", "Bob" finds "Robert" (about 2,800 pairs, see data/nicknames)
# - sound-alikes: "Jon" finds "John", "Smyth" finds "Smith", "Cathy" finds "Kathy" (Double Metaphone)
# - typos:        "Willaim Smtih" finds "William Smith"
# - word order:   "Smith, William" finds "William Smith"
# - partial:      "will smi" finds "William Smith" while typing
# - phone:        any 4+ digits, in any format, matched against both phone numbers
#
# Results are ranked best match first. Only id, name and phone numbers are loaded, and the prepared
# search data is cached until a customer changes, so searching stays fast as the customer list grows.
class CustomerSearchService
  DEFAULT_LIMIT = 20

  # Lowest score (0..1) a customer needs to be returned
  MIN_SCORE = 0.72

  # Bundled nickname data (Apache 2.0, see data/nicknames/README.md)
  NICKNAMES_CSV = File.expand_path('../../data/nicknames/names.csv', __dir__)

  # Groups missing from the bundled data. Add more here: every name in a group matches every other.
  EXTRA_NICKNAME_GROUPS = [
    %w[william liam],
    %w[alexander xander],
    %w[alexandra lexi],
    %w[theodore theo],
    %w[christopher kit]
  ].freeze

  # Words that don't help tell customers apart
  STOP_WORDS = %w[and the llc inc co corp company].freeze

  # Returns matching Customer records, best match first.
  def self.call(name: nil, phone: nil, limit: DEFAULT_LIMIT)
    ids = rank(candidates, name: name, phone: phone, limit: limit).map(&:first)
    return Customer.none if ids.empty?

    Customer.where(id: ids).in_order_of(:id, ids)
  end

  # Prepared search rows for every customer, cached until any customer changes. Kept in this process's
  # memory as well, so each keystroke doesn't reload it from the Rails cache.
  def self.candidates
    key = ['customer_search_candidates', 2, Customer.count, Customer.maximum(:updated_at).to_i]
    cached_key, cached_rows = @candidates
    return cached_rows if cached_key == key

    rows = Rails.cache.fetch(key, expires_in: 12.hours) do
      prepare(Customer.pluck(:id, :name, :phone_number, :mobile_phone_number))
    end
    @candidates = [key, rows]
    rows
  end

  # [[id, name, phone, mobile], ...] -> [[id, name, phone_digits, tokens, sound_codes], ...]
  def self.prepare(rows)
    rows.map do |id, name, phone_number, mobile_number|
      words = tokens(name)
      phones = [phone_number, mobile_number].compact.map { |n| n.to_s.gsub(/\D/, '') }.reject(&:empty?)
      [id, name.to_s, phones, words, words.map { |w| sound_codes(w) }]
    end
  end

  # Pure ranking over prepared rows (no database), so it can be tested on its own.
  # Returns [[id, score], ...] best first. A query of mostly digits is also treated as a phone number.
  def self.rank(prepared, name: nil, phone: nil, limit: DEFAULT_LIMIT)
    name = name.to_s.strip
    phone_digits = phone.to_s.gsub(/\D/, '')

    # "401-555-1234" typed into the name box is a phone search
    name_digits = name.gsub(/\D/, '')
    if phone_digits.empty? && name_digits.length >= 4 && name_digits.length >= name.gsub(/\s/, '').length * 0.7
      phone_digits = name_digits
      name = ''
    end

    query_words = tokens(name)
    return [] if query_words.empty? && phone_digits.length < 4

    query = query_words.map { |w| [w, sound_codes(w)] }
    memo = {} # word-pair scores for this search; customer names repeat words a lot ("smith", "john")

    scored = prepared.filter_map do |id, customer_name, phones, words, codes|
      score = [
        phone_digits.length >= 4 ? phone_score(phone_digits, phones) : 0.0,
        query.any? ? name_score(query, words, codes, memo) : 0.0
      ].max
      [id, score, customer_name] if score >= MIN_SCORE
    end

    scored.sort_by { |id, score, customer_name| [-score, customer_name.downcase, id] }
          .first(limit)
          .map { |id, score, _| [id, score.round(3)] }
  end

  # Lowercase words with accents and punctuation removed: "O'Brien-Smith, José" -> ["obrien", "smith", "jose"]
  def self.tokens(text)
    normalized = text.to_s.unicode_normalize(:nfkd).gsub(/\p{Mn}/, '').downcase
    normalized = normalized.gsub(/['’]/, '').gsub(/[^a-z0-9]+/, ' ')
    words = normalized.split
    meaningful = words - STOP_WORDS
    meaningful.empty? ? words : meaningful
  end

  # Double Metaphone codes (primary and alternate) for a word; empty for very short or numeric words
  def self.sound_codes(word)
    return [] if word.length < 3 || word.match?(/\d/)

    Text::Metaphone.double_metaphone(word).compact.reject(&:empty?).uniq
  end

  def self.phone_score(digits, phones)
    phones.map do |number|
      if number == digits || number.end_with?(digits) && digits.length >= 7 then 1.0
      elsif number.include?(digits) then 0.9
      else 0.0
      end
    end.max || 0.0
  end

  # Each query word is matched to its best word in the customer's name; the score is the average.
  # A query word with no match at all halves the score, so "bill jones" won't match "william smith".
  def self.name_score(query, words, codes, memo = {})
    return 0.0 if words.empty?

    best = query.map do |q_word, q_codes|
      scores = (memo[q_word] ||= {})
      words.each_with_index.map do |c_word, i|
        scores.fetch(c_word) { scores[c_word] = word_score(q_word, q_codes, c_word, codes[i]) }
      end.max
    end
    score = best.sum / best.size
    score *= 0.5 if best.any?(&:zero?)

    return score if score >= 0.9 # already a strong match; skip the whole-name comparison

    # Also compare the names with spaces removed, for "Mc Donald" vs "McDonald". Only worth it when the
    # strings could reach the 0.92 bar at all: same first letter and nearly the same length.
    query_joined = query.map(&:first).join
    name_joined = words.join
    return score unless query_joined[0] == name_joined[0] && (query_joined.length - name_joined.length).abs <= 2

    joined = DidYouMean::JaroWinkler.distance(query_joined, name_joined)
    [score, joined >= 0.92 ? joined * 0.9 : 0.0].max
  end

  def self.word_score(query, query_codes, candidate, candidate_codes)
    return 1.0 if query == candidate
    return 0.95 if nicknames?(query, candidate)
    return 0.9 if query.length >= 2 && candidate.start_with?(query)          # still typing: "wil" -> "william"
    return 0.85 if query.length >= 2 && nickname_prefix?(query, candidate)  # "bil" -> "william" via "bill"

    similarity = DidYouMean::JaroWinkler.distance(query, candidate)

    # Sounds the same ("jon"/"john", "smyth"/"smith"). The similarity check keeps unrelated words that
    # happen to share a code (e.g. "john" and "ann" via the Spanish-J alternate) from matching.
    return 0.88 if similarity >= 0.7 && (query_codes & candidate_codes).any?

    return 0.8 if query.length >= 4 && candidate.include?(query)            # "donald" in "mcdonald"
    return 0.7 if query.length == 1 && candidate.start_with?(query)         # an initial

    # Typos. Short words need to be closer to count.
    threshold = [query.length, candidate.length].min <= 4 ? 0.9 : 0.85
    similarity >= threshold ? similarity * 0.9 : 0.0
  end

  # Nickname matching treats the data as connections between names (the file lists both directions,
  # e.g. "william -> bill" and "bill -> william"). Two names match if they are connected directly, or both
  # connect to a LONGER name they're short for: "bill" and "will" via "william". Requiring the shared
  # name to be longer stops unrelated full names linking through a short one: "bill" is listed for both
  # William and Robert, but that doesn't make William match Robert.
  def self.nicknames?(a, b)
    related_names(a).include?(b)
  end

  # A partly typed nickname of the candidate's name, e.g. "bil" for "william" (via "bill")
  def self.nickname_prefix?(query, candidate)
    related_names(candidate).any? { |name| name.start_with?(query) }
  end

  # All names interchangeable with name, cached per process
  def self.related_names(name)
    cache = (@related_names_cache ||= {})
    cache[name] ||= begin
      graph = nickname_graph
      direct = graph.fetch(name, EMPTY)
      through_full_names = direct.select { |full| full.length > name.length }.flat_map do |full|
        graph.fetch(full, EMPTY).select { |other| other.length < full.length }
      end
      ((direct + through_full_names).uniq - [name]).freeze
    end
  end

  EMPTY = [].freeze

  # name => [connected names], built once per process from the bundled data plus EXTRA_NICKNAME_GROUPS
  def self.nickname_graph
    @nickname_graph ||= begin
      graph = Hash.new { |h, k| h[k] = [] }
      connect = lambda do |a, b|
        next if a.empty? || b.empty? || a == b

        graph[a] << b
        graph[b] << a
      end

      if File.exist?(NICKNAMES_CSV)
        CSV.foreach(NICKNAMES_CSV, headers: true) do |row|
          connect.call(row['name1'].to_s.strip.downcase, row['name2'].to_s.strip.downcase)
        end
      end

      EXTRA_NICKNAME_GROUPS.each do |group|
        group.combination(2) { |a, b| connect.call(a, b) }
      end

      graph.transform_values { |names| names.uniq.freeze }.to_h.freeze
    end
  end
end

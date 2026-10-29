#The MIT License (MIT)
#
#Copyright (c) 2016 - 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

require 'did_you_mean'

# Finds customers by name and/or phone, tolerant of the ways duplicates sneak in:
# - nicknames:   "Bill Smith" finds "William Smith", "Bob" finds "Robert"
# - typos:       "Willaim Smtih" finds "William Smith"
# - word order:  "Smith William" or "Smith, William" finds "William Smith"
# - partial:     "will smi" finds "William Smith" while typing
# - phone:       any 4+ digits, in any format, matched against both phone numbers
#
# Results are ranked best match first. Only id, name and phone numbers are loaded (and cached until
# a customer changes), so searching stays fast as the customer list grows.
class CustomerSearchService
  DEFAULT_LIMIT = 20

  # Lowest score (0..1) a customer needs to be returned
  MIN_SCORE = 0.72

  # Groups of interchangeable first names. A name may appear in more than one group (e.g. "chris").
  NICKNAME_GROUPS = [
    %w[william bill billy will willy willie liam],
    %w[robert bob bobby rob robbie bert],
    %w[richard rick ricky rich richie dick],
    %w[james jim jimmy jamie],
    %w[john jack johnny jon],
    %w[jonathan jon jonny],
    %w[michael mike mikey mick],
    %w[thomas tom tommy],
    %w[joseph joe joey],
    %w[charles charlie chuck chas],
    %w[edward ed eddie ted ned],
    %w[anthony tony],
    %w[christopher chris kit],
    %w[christine christina chris tina],
    %w[daniel dan danny],
    %w[david dave davey],
    %w[matthew matt],
    %w[andrew andy drew],
    %w[steven stephen steve stevie],
    %w[benjamin ben benny],
    %w[samuel sam sammy],
    %w[samantha sam],
    %w[alexander alex al xander],
    %w[alexandra alex lexi],
    %w[albert al bert],
    %w[nicholas nick nicky],
    %w[patrick pat],
    %w[patricia pat patty trish],
    %w[peter pete],
    %w[timothy tim timmy],
    %w[kenneth ken kenny],
    %w[ronald ron ronnie],
    %w[donald don donnie],
    %w[gregory greg],
    %w[jeffrey jeff],
    %w[gerald jerry gerry],
    %w[lawrence larry],
    %w[raymond ray],
    %w[frederick fred freddie],
    %w[theodore ted teddy theo],
    %w[douglas doug],
    %w[joshua josh],
    %w[zachary zach zack],
    %w[nathaniel nathan nate],
    %w[elizabeth liz lizzie beth betty eliza],
    %w[margaret maggie meg peggy],
    %w[katherine catherine kathryn kate katie kathy cathy kat],
    %w[jennifer jen jenny],
    %w[rebecca becky becca],
    %w[susan sue susie],
    %w[deborah debra deb debbie],
    %w[victoria vicky tori],
    %w[jessica jess jessie]
  ].freeze

  # name => indexes of the groups it belongs to
  NICKNAME_INDEX = NICKNAME_GROUPS.each_with_index.with_object(Hash.new { |h, k| h[k] = [] }) do |(group, index), map|
    group.each { |name| map[name] << index }
  end.freeze

  # Words that don't help tell customers apart
  STOP_WORDS = %w[and the llc inc co corp company].freeze

  # Returns matching Customer records, best match first.
  def self.call(name: nil, phone: nil, limit: DEFAULT_LIMIT)
    ids = rank(candidates, name: name, phone: phone, limit: limit).map(&:first)
    return Customer.none if ids.empty?

    Customer.where(id: ids).in_order_of(:id, ids)
  end

  # [[id, name, phone_number, mobile_phone_number], ...], cached until any customer changes
  def self.candidates
    key = ['customer_search_candidates', Customer.count, Customer.maximum(:updated_at).to_i]
    Rails.cache.fetch(key, expires_in: 12.hours) do
      Customer.pluck(:id, :name, :phone_number, :mobile_phone_number)
    end
  end

  # Pure ranking (no database), so it can be tested on its own.
  # Returns [[id, score], ...] best first. A query of mostly digits is also treated as a phone number.
  def self.rank(rows, name: nil, phone: nil, limit: DEFAULT_LIMIT)
    name = name.to_s.strip
    phone_digits = phone.to_s.gsub(/\D/, '')

    # "401-555-1234" typed into the name box is a phone search
    name_digits = name.gsub(/\D/, '')
    if phone_digits.empty? && name_digits.length >= 4 && name_digits.length >= name.gsub(/\s/, '').length * 0.7
      phone_digits = name_digits
      name = ''
    end

    query_tokens = tokens(name)
    return [] if query_tokens.empty? && phone_digits.length < 4

    scored = rows.filter_map do |id, customer_name, phone_number, mobile_number|
      score = [
        phone_digits.length >= 4 ? phone_score(phone_digits, [phone_number, mobile_number]) : 0.0,
        query_tokens.any? ? name_score(query_tokens, customer_name) : 0.0
      ].max
      [id, score, customer_name.to_s] if score >= MIN_SCORE
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

  def self.phone_score(digits, numbers)
    numbers.compact.map { |n| n.to_s.gsub(/\D/, '') }.reject(&:empty?).map do |number|
      if number == digits || number.end_with?(digits) && digits.length >= 7 then 1.0
      elsif number.include?(digits) then 0.9
      else 0.0
      end
    end.max || 0.0
  end

  # Each query word is matched to its best word in the customer's name; the score is the average.
  # A query word with no match at all halves the score, so "bill jones" won't match "william smith".
  def self.name_score(query_tokens, customer_name)
    name_tokens = tokens(customer_name)
    return 0.0 if name_tokens.empty?

    best = query_tokens.map { |q| name_tokens.map { |c| token_score(q, c) }.max }
    score = best.sum / best.size
    score *= 0.5 if best.any?(&:zero?)

    # Also compare the names with spaces removed, for "Mc Donald" vs "McDonald"
    joined = DidYouMean::JaroWinkler.distance(query_tokens.join, name_tokens.join)
    [score, joined >= 0.92 ? joined * 0.9 : 0.0].max
  end

  def self.token_score(query, candidate)
    return 1.0 if query == candidate
    return 0.95 if nicknames?(query, candidate)
    return 0.9 if query.length >= 2 && candidate.start_with?(query)          # still typing: "wil" -> "william"
    return 0.85 if query.length >= 2 && nickname_prefix?(query, candidate)  # "bil" -> "william" via "bill"
    return 0.8 if query.length >= 4 && candidate.include?(query)            # "donald" in "mcdonald"
    return 0.7 if query.length == 1 && candidate.start_with?(query)         # an initial

    # Typos. Short words need to be closer to count.
    similarity = DidYouMean::JaroWinkler.distance(query, candidate)
    threshold = [query.length, candidate.length].min <= 4 ? 0.9 : 0.85
    similarity >= threshold ? similarity * 0.9 : 0.0
  end

  def self.nicknames?(a, b)
    (NICKNAME_INDEX.fetch(a, []) & NICKNAME_INDEX.fetch(b, [])).any?
  end

  # A partly typed nickname of the candidate's name, e.g. "bil" for "william"
  def self.nickname_prefix?(query, candidate)
    NICKNAME_INDEX.fetch(candidate, []).any? do |index|
      NICKNAME_GROUPS[index].any? { |name| name != candidate && name.start_with?(query) }
    end
  end
end

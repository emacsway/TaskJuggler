require 'taskjuggler/SyntaxReference'

# Extracts syntax keyword information from the TJ3 engine's SyntaxReference.
# Returns context map and value map built from the actual parser rules.
class Tj3SyntaxExtractor
  def self.extract
    @cache ||= build_syntax_map
  end

  def self.build_syntax_map
    ref = TaskJuggler::SyntaxReference.new(nil, true)
    parser = ref.instance_variable_get(:@parser)

    result = {}

    ref.keywords.each do |keyword_name, kwd|
      contexts = kwd.contexts.map { |c| c.keyword.to_s rescue c.to_s }

      children = kwd.optionalAttributes.map do |attr|
        name = attr.respond_to?(:keyword) ? attr.keyword : attr.to_s
        name = name.split('.').last if name.include?('.')
        name
      end.uniq.sort

      entry = {
        keyword: keyword_name,
        names: kwd.names,
        contexts: contexts,
        children: children,
        scenarioSpecific: kwd.scenarioSpecific,
        inheritedFromProject: kwd.inheritedFromProject,
        inheritedFromParent: kwd.inheritedFromParent,
      }

      result[keyword_name] = entry
    end

    # Build context map: block keyword -> valid children
    context_map = {}
    result.each do |keyword_name, entry|
      next if entry[:children].empty?
      base = keyword_name.split('.').last
      context_map[base] ||= []
      context_map[base] = (context_map[base] + entry[:children]).uniq.sort
    end

    # Build value map: keyword -> list of valid enum values
    # Extract from parser rules that reference enum-like sub-rules
    value_map = {}
    if parser
      ref.keywords.each do |keyword_name, kwd|
        pattern = kwd.pattern
        next unless pattern

        tokens = pattern.tokens rescue []
        tokens.each do |token|
          next unless token.is_a?(Array) && token[0] == :reference

          rule_sym = token[1]
          rule = parser.rules[rule_sym] rescue nil
          next unless rule

          # Collect all literal tokens from this rule's patterns
          values = []
          rule.patterns.each do |p|
            p.tokens.each do |t|
              if t.is_a?(Array) && t[0] == :literal
                values << t[1].to_s
              end
            end
          end

          if values.any?
            base = keyword_name.split('.').last
            value_map[base] = ((value_map[base] || []) + values).uniq.sort
          end
        end
      end
    end

    # Build docs map: keyword -> short description (for hover)
    docs_map = {}
    # Build full docs: keyword -> { full doc, seeAlso, contexts, scenarioSpecific, children }
    full_docs = {}

    ref.keywords.each do |keyword_name, kwd|
      doc = kwd.pattern.doc rescue nil
      base = keyword_name.split('.').last

      if doc && !doc.strip.empty?
        docs_map[base] ||= doc.strip.gsub(/\s+/, ' ').slice(0, 300)
      end

      see_also = (kwd.instance_variable_get(:@seeAlso) || []).map { |s| s.keyword rescue s.to_s }
      contexts = kwd.contexts.map { |c| c.keyword.to_s rescue c.to_s }
      children = kwd.optionalAttributes.map { |a|
        n = a.respond_to?(:keyword) ? a.keyword : a.to_s
        n.include?('.') ? n.split('.').last : n
      }.uniq.sort

      syntax_str = begin
        kwd.pattern.to_s
      rescue
        keyword_name
      end

      full_docs[base] ||= {
        keyword: base,
        fullDoc: doc&.strip || '',
        syntax: syntax_str.to_s,
        seeAlso: see_also,
        contexts: contexts,
        children: children,
        scenarioSpecific: kwd.scenarioSpecific,
        inheritedFromProject: kwd.inheritedFromProject,
        inheritedFromParent: kwd.inheritedFromParent,
      }
    end

    {
      keywords: result,
      contextMap: context_map,
      valueMap: value_map,
      docsMap: docs_map,
      fullDocs: full_docs,
    }
  rescue => e
    $stderr.puts "SyntaxExtractor error: #{e.message}\n#{e.backtrace.first(3).join("\n")}"
    { keywords: {}, contextMap: {}, valueMap: {} }
  end
end

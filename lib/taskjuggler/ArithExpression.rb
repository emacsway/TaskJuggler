#!/usr/bin/env ruby -w
# frozen_string_literal: true
# encoding: UTF-8
#
# = ArithExpression.rb -- The TaskJuggler III Project Management Software
#
# Arithmetic expression AST and evaluator for computed report columns.
# Supports: +, -, *, /, attribute references, literals, aggregate functions.
#
# Example: sum(effort * complete / 100)
#

require 'taskjuggler/Query'

class TaskJuggler

  # Base class for arithmetic expression nodes
  class ArithExpr
    def eval_for(query)
      raise NotImplementedError
    end
  end

  # Numeric literal: 100, 0.5
  class ArithLiteral < ArithExpr
    def initialize(value)
      @value = value.to_f
    end

    def eval_for(_query)
      @value
    end

    def to_s
      @value == @value.to_i ? @value.to_i.to_s : @value.to_s
    end
  end

  # Reference to a task/resource attribute: effort, complete, effortleft
  class ArithAttributeRef < ArithExpr
    attr_reader :name

    def initialize(name)
      @name = name
    end

    def eval_for(query)
      q = query.dup
      q.attributeId = @name
      q.process
      q.ok ? (q.to_num rescue 0.0) : 0.0
    end

    def to_s
      @name
    end
  end

  # Binary operation: left op right
  class ArithBinaryOp < ArithExpr
    def initialize(op, left, right)
      @op = op
      @left = left
      @right = right
    end

    def eval_for(query)
      l = @left.eval_for(query)
      r = @right.eval_for(query)
      case @op
      when :+ then l + r
      when :- then l - r
      when :* then l * r
      when :/ then r != 0 ? l / r : 0.0
      else 0.0
      end
    end

    def to_s
      "(#{@left} #{@op} #{@right})"
    end
  end

  # Aggregate function: sum, avg, count, min, max
  class ArithAggregate < ArithExpr
    attr_reader :func, :inner

    def initialize(func, inner)
      @func = func.to_sym  # :sum, :avg, :count, :min, :max
      @inner = inner
    end

    # Evaluate aggregate over a list of properties (tasks/resources)
    def eval_aggregate(query, property_list)
      values = []
      property_list.each do |prop|
        q = query.dup
        q.property = prop
        val = @inner.eval_for(q)
        values << val if val
      end

      return nil if values.empty?

      case @func
      when :sum   then values.sum
      when :avg   then values.sum / values.size
      when :count then values.size.to_f
      when :min   then values.min
      when :max   then values.max
      else values.sum
      end
    end

    def to_s
      "#{@func}(#{@inner})"
    end
  end

  # Parser for arithmetic expressions.
  # Grammar:
  #   expr     := term (('+' | '-') term)*
  #   term     := factor (('*' | '/') factor)*
  #   factor   := NUMBER | IDENTIFIER | func_call | '(' expr ')'
  #   func_call := ('sum'|'avg'|'count'|'min'|'max') '(' expr ')'
  class ArithExprParser
    AGGREGATE_FUNCS = %w[sum avg count min max].freeze

    def initialize(input)
      @tokens = tokenize(input)
      @pos = 0
    end

    def parse
      expr = parse_expr
      raise "Unexpected token: #{current}" if @pos < @tokens.size
      expr
    end

    private

    def tokenize(input)
      tokens = []
      s = input.strip
      i = 0
      while i < s.length
        case s[i]
        when /\s/
          i += 1
        when '+', '-', '*', '/', '(', ')', ','
          tokens << s[i]
          i += 1
        when /\d/
          num = ''
          while i < s.length && s[i] =~ /[\d.]/
            num += s[i]
            i += 1
          end
          tokens << [:num, num.to_f]
        when /[a-zA-Z_]/
          id = ''
          while i < s.length && s[i] =~ /[a-zA-Z_0-9]/
            id += s[i]
            i += 1
          end
          tokens << [:id, id]
        else
          raise "Unexpected character: '#{s[i]}' in expression '#{input}'"
        end
      end
      tokens
    end

    def current
      @tokens[@pos]
    end

    def consume(expected = nil)
      tok = @tokens[@pos]
      if expected && tok != expected
        raise "Expected '#{expected}', got '#{tok}'"
      end
      @pos += 1
      tok
    end

    def parse_expr
      left = parse_term
      while current == '+' || current == '-'
        op = consume == '+' ? :+ : :-
        right = parse_term
        left = ArithBinaryOp.new(op, left, right)
      end
      left
    end

    def parse_term
      left = parse_factor
      while current == '*' || current == '/'
        op = consume == '*' ? :* : :/
        right = parse_factor
        left = ArithBinaryOp.new(op, left, right)
      end
      left
    end

    def parse_factor
      tok = current
      if tok.is_a?(Array) && tok[0] == :num
        consume
        ArithLiteral.new(tok[1])
      elsif tok.is_a?(Array) && tok[0] == :id
        consume
        name = tok[1]
        if AGGREGATE_FUNCS.include?(name)
          consume('(')
          inner = parse_expr
          consume(')')
          ArithAggregate.new(name, inner)
        else
          ArithAttributeRef.new(name)
        end
      elsif tok == '('
        consume('(')
        expr = parse_expr
        consume(')')
        expr
      elsif tok == '-'
        consume
        factor = parse_factor
        ArithBinaryOp.new(:*, ArithLiteral.new(-1), factor)
      else
        raise "Unexpected token: #{tok.inspect}"
      end
    end
  end

end

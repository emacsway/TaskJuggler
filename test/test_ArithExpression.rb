#!/usr/bin/env ruby -w
# frozen_string_literal: true
# encoding: UTF-8

$:.unshift File.join(File.dirname(__FILE__), '..', 'lib') if __FILE__ == $0
$:.unshift File.dirname(__FILE__)

require 'test/unit'
require 'taskjuggler/ArithExpression'

class TestArithExpression < Test::Unit::TestCase

  # ── Parser tests ────────────────────────────────────────────

  def test_parse_literal
    expr = TaskJuggler::ArithExprParser.new("42").parse
    assert_instance_of(TaskJuggler::ArithLiteral, expr)
  end

  def test_parse_float
    expr = TaskJuggler::ArithExprParser.new("3.14").parse
    assert_instance_of(TaskJuggler::ArithLiteral, expr)
  end

  def test_parse_attribute
    expr = TaskJuggler::ArithExprParser.new("effort").parse
    assert_instance_of(TaskJuggler::ArithAttributeRef, expr)
    assert_equal("effort", expr.name)
  end

  def test_parse_addition
    expr = TaskJuggler::ArithExprParser.new("effort + 10").parse
    assert_instance_of(TaskJuggler::ArithBinaryOp, expr)
  end

  def test_parse_multiplication
    expr = TaskJuggler::ArithExprParser.new("effort * complete").parse
    assert_instance_of(TaskJuggler::ArithBinaryOp, expr)
  end

  def test_parse_complex
    expr = TaskJuggler::ArithExprParser.new("effort * complete / 100").parse
    assert_instance_of(TaskJuggler::ArithBinaryOp, expr)
    assert_equal("((effort * complete) / 100)", expr.to_s)
  end

  def test_parse_parentheses
    expr = TaskJuggler::ArithExprParser.new("(effort - effortdone) * 2").parse
    assert_equal("((effort - effortdone) * 2)", expr.to_s)
  end

  def test_parse_negative
    expr = TaskJuggler::ArithExprParser.new("-5").parse
    assert_instance_of(TaskJuggler::ArithBinaryOp, expr)
  end

  def test_parse_sum
    expr = TaskJuggler::ArithExprParser.new("sum(effort)").parse
    assert_instance_of(TaskJuggler::ArithAggregate, expr)
    assert_equal(:sum, expr.func)
  end

  def test_parse_avg
    expr = TaskJuggler::ArithExprParser.new("avg(complete)").parse
    assert_instance_of(TaskJuggler::ArithAggregate, expr)
    assert_equal(:avg, expr.func)
  end

  def test_parse_count
    expr = TaskJuggler::ArithExprParser.new("count(effort)").parse
    assert_equal(:count, expr.func)
  end

  def test_parse_min_max
    min_expr = TaskJuggler::ArithExprParser.new("min(effort)").parse
    max_expr = TaskJuggler::ArithExprParser.new("max(effort)").parse
    assert_equal(:min, min_expr.func)
    assert_equal(:max, max_expr.func)
  end

  def test_parse_sum_complex
    expr = TaskJuggler::ArithExprParser.new("sum(effort * complete / 100)").parse
    assert_instance_of(TaskJuggler::ArithAggregate, expr)
    assert_equal("sum(((effort * complete) / 100))", expr.to_s)
  end

  def test_parse_round
    expr = TaskJuggler::ArithExprParser.new("round(3.14)").parse
    assert_instance_of(TaskJuggler::ArithRound, expr)
  end

  def test_parse_round_with_digits
    expr = TaskJuggler::ArithExprParser.new("round(3.14, 1)").parse
    assert_instance_of(TaskJuggler::ArithRound, expr)
    assert_equal("round(3.14, 1)", expr.to_s)
  end

  def test_parse_round_sum
    expr = TaskJuggler::ArithExprParser.new("round(sum(effort), 2)").parse
    assert_instance_of(TaskJuggler::ArithRound, expr)
    assert(expr.aggregate?, "round(sum(...)) should be aggregate")
  end

  def test_parse_error
    assert_raise(RuntimeError) {
      TaskJuggler::ArithExprParser.new("@invalid").parse
    }
  end

  def test_parse_unbalanced_parens
    assert_raise(RuntimeError) {
      TaskJuggler::ArithExprParser.new("(effort + 1").parse
    }
  end

  # ── Evaluator tests (literals only) ─────────────────────────

  def test_eval_literal
    expr = TaskJuggler::ArithExprParser.new("42").parse
    assert_equal(42.0, expr.eval_for(nil))
  end

  def test_eval_addition
    expr = TaskJuggler::ArithExprParser.new("10 + 20").parse
    assert_equal(30.0, expr.eval_for(nil))
  end

  def test_eval_subtraction
    expr = TaskJuggler::ArithExprParser.new("50 - 15").parse
    assert_equal(35.0, expr.eval_for(nil))
  end

  def test_eval_multiplication
    expr = TaskJuggler::ArithExprParser.new("6 * 7").parse
    assert_equal(42.0, expr.eval_for(nil))
  end

  def test_eval_division
    expr = TaskJuggler::ArithExprParser.new("100 / 4").parse
    assert_equal(25.0, expr.eval_for(nil))
  end

  def test_eval_division_by_zero
    expr = TaskJuggler::ArithExprParser.new("10 / 0").parse
    assert_equal(0.0, expr.eval_for(nil))
  end

  def test_eval_precedence
    # * before +
    expr = TaskJuggler::ArithExprParser.new("2 + 3 * 4").parse
    assert_equal(14.0, expr.eval_for(nil))
  end

  def test_eval_parentheses
    expr = TaskJuggler::ArithExprParser.new("(2 + 3) * 4").parse
    assert_equal(20.0, expr.eval_for(nil))
  end

  def test_eval_complex
    # 10 * 50 / 100 = 5
    expr = TaskJuggler::ArithExprParser.new("10 * 50 / 100").parse
    assert_equal(5.0, expr.eval_for(nil))
  end

  def test_eval_round
    expr = TaskJuggler::ArithExprParser.new("round(3.14159)").parse
    assert_equal(3, expr.eval_for(nil))
  end

  def test_eval_round_digits
    expr = TaskJuggler::ArithExprParser.new("round(3.14159, 2)").parse
    assert_equal(3.14, expr.eval_for(nil))
  end

  def test_eval_round_one_digit
    expr = TaskJuggler::ArithExprParser.new("round(88.34363, 1)").parse
    assert_equal(88.3, expr.eval_for(nil))
  end

  def test_eval_negative
    expr = TaskJuggler::ArithExprParser.new("-5 + 3").parse
    assert_equal(-2.0, expr.eval_for(nil))
  end

  # ── Aggregate tests ─────────────────────────────────────────

  def test_aggregate_detection
    sum_expr = TaskJuggler::ArithExprParser.new("sum(effort)").parse
    assert_instance_of(TaskJuggler::ArithAggregate, sum_expr)

    round_sum = TaskJuggler::ArithExprParser.new("round(sum(effort), 1)").parse
    assert(round_sum.aggregate?, "round(sum) should be detected as aggregate")

    plain = TaskJuggler::ArithExprParser.new("effort * 2").parse
    assert(!plain.aggregate?)
  end

  def test_aggregate_in_binary_op
    expr = TaskJuggler::ArithExprParser.new("sum(effort) / sum(effort) * 100").parse
    assert(expr.aggregate?, "sum(x) / sum(x) * 100 should be aggregate")
  end

  def test_mixed_aggregate_and_literal
    expr = TaskJuggler::ArithExprParser.new("sum(effort) + 10").parse
    assert(expr.aggregate?, "sum(effort) + 10 should be aggregate")
  end

  def test_non_aggregate_binary
    expr = TaskJuggler::ArithExprParser.new("effort + 10").parse
    assert(!expr.aggregate?, "effort + 10 should not be aggregate")
  end

  # ── to_s roundtrip tests ────────────────────────────────────

  def test_to_s_literal
    assert_equal("42", TaskJuggler::ArithExprParser.new("42").parse.to_s)
  end

  def test_to_s_attribute
    assert_equal("effort", TaskJuggler::ArithExprParser.new("effort").parse.to_s)
  end

  def test_to_s_aggregate
    assert_equal("sum(effort)", TaskJuggler::ArithExprParser.new("sum(effort)").parse.to_s)
  end

  def test_to_s_round
    assert_equal("round(3.14, 2)", TaskJuggler::ArithExprParser.new("round(3.14, 2)").parse.to_s)
  end
end

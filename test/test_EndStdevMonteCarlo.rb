#!/usr/bin/env ruby -w
# frozen_string_literal: true
# encoding: UTF-8
#
# = test_EndStdevMonteCarlo.rb -- The TaskJuggler III Project Management Software
#
# Monte Carlo validation of the PERT method-of-moments propagation
# used by TaskScenario#endStdevSlots. Each test samples task effort
# from a normal distribution, propagates through a DAG by the same
# rules as the TJ3 scheduler (sum along chains, max at merges),
# records the empirical distribution of the target task's end date,
# and compares its standard deviation against the analytical PERT
# estimate that uses Clark-1961 merging at merge points.
#
# The tests cover:
#
# 1. CHAIN — no merges, PERT is exact (σ = √Σσ_dur²).
# 2. DIAMOND with DOMINANT critical path — well-separated means, Clark
#    reduces to the critical-path rule; estimate matches MC within a
#    few percent.
# 3. DIAMOND with EQUAL iid branches — the classical trap where the
#    critical-path rule overestimates σ. Clark's closed form captures
#    σ_max/σ = √(1 − 1/π) ≈ 0.826 and matches MC.
# 4. DIAMOND with asymmetric near-critical merge (high-σ runner-up
#    just below the mean-critical path). The critical-path rule would
#    underestimate σ; Clark accounts for the runner-up's variance.
#
# Both the critical-path rule (kept here as a reference) and the Clark
# rule are computed on the abstract spec; the Clark rule is the one
# TaskScenario#endStdevSlots uses. Gaps between the two rules on the
# same topology are what motivate the Clark implementation.
#

$:.unshift File.join(File.dirname(__FILE__), '..', 'lib') if __FILE__ == $0
$:.unshift File.dirname(__FILE__)

require 'test/unit'
require 'taskjuggler/ClarkMerge'

class TestEndStdevMonteCarlo < Test::Unit::TestCase

  # Task spec: name => { duration_mean, duration_stdev, depends }
  # Returns empirical stdev of end_date across N samples.
  def monte_carlo(tasks_spec, target_task, n: 20_000, seed: 42)
    rng = Random.new(seed)
    ends = Array.new(n) do
      end_dates = {}
      topo_order(tasks_spec).each do |name|
        spec = tasks_spec[name]
        # Sample duration from N(mean, stdev), truncate at 0.
        dur = rng.rand * 0 + gaussian(rng, spec[:mean], spec[:stdev])
        dur = 0.0 if dur < 0.0
        preds_end = spec[:depends].map { |d| end_dates.fetch(d) }
        start_time = preds_end.empty? ? 0.0 : preds_end.max
        end_dates[name] = start_time + dur
      end
      end_dates[target_task]
    end
    empirical_stdev(ends)
  end

  def topo_order(tasks_spec)
    # Kahn's algorithm for topological sort.
    indeg = {}
    tasks_spec.each_key { |n| indeg[n] = 0 }
    tasks_spec.each do |name, spec|
      spec[:depends].each { |_| indeg[name] += 1 }
    end
    order = []
    queue = indeg.select { |_, d| d == 0 }.keys
    while (n = queue.shift)
      order << n
      tasks_spec.each do |other, spec|
        if spec[:depends].include?(n)
          indeg[other] -= 1
          queue << other if indeg[other] == 0
        end
      end
    end
    order
  end

  def gaussian(rng, mu, sigma)
    # Box-Muller transform.
    u1, u2 = rng.rand, rng.rand
    z = Math.sqrt(-2.0 * Math.log(u1)) * Math.cos(2.0 * Math::PI * u2)
    mu + sigma * z
  end

  def empirical_stdev(xs)
    mean = xs.sum / xs.size
    var = xs.sum { |x| (x - mean) ** 2 } / (xs.size - 1)
    Math.sqrt(var)
  end

  # PERT σ computed with the naive critical-path rule: at merge points
  # take σ from the predecessor with the largest mean end. Kept for
  # reference so we can quantify what Clark's correction buys.
  def pert_critical_path_stdev(tasks_spec, target)
    memo = {}
    compute = lambda do |name|
      return memo[name] if memo.key?(name)
      spec = tasks_spec[name]
      if spec[:depends].empty?
        result = [spec[:mean], spec[:stdev]]
      else
        pred_stats = spec[:depends].map { |d| compute.call(d) }
        crit = pred_stats.max_by { |m, s| [m, s] }
        start_mean, start_sigma = crit
        result = [start_mean + spec[:mean],
                  Math.sqrt(start_sigma**2 + spec[:stdev]**2)]
      end
      memo[name] = result
    end
    compute.call(target)[1]
  end

  # PERT σ with Clark-1961 merging at merge points — mirrors the rule
  # TaskScenario#endStdevSlots uses.
  def pert_clark_stdev(tasks_spec, target)
    memo = {}
    compute = lambda do |name|
      return memo[name] if memo.key?(name)
      spec = tasks_spec[name]
      if spec[:depends].empty?
        result = [spec[:mean], spec[:stdev]]
      else
        pred_stats = spec[:depends].map { |d| compute.call(d) }
        # Merge predecessor end moments via Clark to obtain σ of their max.
        start_mean, start_sigma = TaskJuggler::ClarkMerge.reduce(pred_stats)
        result = [start_mean + spec[:mean],
                  Math.sqrt(start_sigma**2 + spec[:stdev]**2)]
      end
      memo[name] = result
    end
    compute.call(target)[1]
  end

  # ─── Chain: no merges, Clark == critical-path ───────────────

  def test_chain_pert_matches_mc
    # A → B → C. Each mean=10, stdev=2. Expected: σ = √(3·2²) = 2√3 ≈ 3.46.
    spec = {
      'a' => { mean: 10.0, stdev: 2.0, depends: [] },
      'b' => { mean: 10.0, stdev: 2.0, depends: ['a'] },
      'c' => { mean: 10.0, stdev: 2.0, depends: ['b'] }
    }
    clark = pert_clark_stdev(spec, 'c')
    crit  = pert_critical_path_stdev(spec, 'c')
    mc    = monte_carlo(spec, 'c')
    assert_in_delta(Math.sqrt(3) * 2.0, clark, 1e-9,
                    "Chain Clark-PERT: σ = √3·2")
    assert_in_delta(clark, crit, 1e-12,
                    "Chain has no merges: Clark = critical-path")
    assert((clark - mc).abs / mc < 0.03,
           "Chain Clark should match MC within 3%, got rel_err=#{(clark - mc).abs / mc}")
  end

  # ─── Diamond with dominant critical path ─────────────────────

  def test_diamond_dominant_critical_path
    # Three parallel leaves with very different means — the longest
    # dominates by many σ. Clark reduces to critical-path here.
    spec = {
      'a' => { mean: 3.0,  stdev: 0.5, depends: [] },
      'b' => { mean: 5.0,  stdev: 0.5, depends: [] },
      'c' => { mean: 20.0, stdev: 0.5, depends: [] },
      'd' => { mean: 5.0,  stdev: 0.5, depends: ['a', 'b', 'c'] }
    }
    clark = pert_clark_stdev(spec, 'd')
    crit  = pert_critical_path_stdev(spec, 'd')
    mc    = monte_carlo(spec, 'd')
    assert((clark - crit).abs / crit < 0.001,
           "Dominant critical path: Clark should agree with critical-path rule, got gap=#{(clark - crit).abs / crit}")
    assert((clark - mc).abs / mc < 0.05,
           "Dominant critical path: Clark should match MC within 5%, got rel_err=#{(clark - mc).abs / mc}")
  end

  # ─── Equal iid branches: where critical-path is WRONG ───────

  def test_diamond_equal_iid_branches_clark_matches_mc
    # Two identical N(10, 4) branches. Max-of-two-iid has
    # σ_max = σ·√(1 − 1/π) ≈ 0.826·σ. Critical-path rule reports σ
    # directly, OVERSTATING by ~21%; Clark captures the true ratio.
    spec = {
      'a' => { mean: 10.0, stdev: 2.0, depends: [] },
      'b' => { mean: 10.0, stdev: 2.0, depends: [] },
      'd' => { mean: 1.0,  stdev: 0.1, depends: ['a', 'b'] }
    }
    clark = pert_clark_stdev(spec, 'd')
    crit  = pert_critical_path_stdev(spec, 'd')
    mc    = monte_carlo(spec, 'd')

    # Critical-path rule is biased high — quantify the gap so a
    # regression that reverted Clark would be caught.
    assert(crit > mc,
           "Sanity: critical-path rule overestimates σ for equal iid branches")
    # Clark should close most of that gap.
    assert((clark - mc).abs / mc < 0.03,
           "Equal iid branches: Clark should match MC within 3%, got rel_err=#{(clark - mc).abs / mc}")
    # Closed-form ratio mc/crit ≈ √(1 − 1/π) ≈ 0.826 (ignoring σ_d=0.1
    # which is small relative to 2.0).
    assert(mc / crit > 0.80 && mc / crit < 0.90,
           "Sanity: mc/crit should be near √(1 − 1/π) ≈ 0.826, got #{mc / crit}")
  end

  def test_diamond_asymmetric_branches_clark_matches_mc
    # Critical branch: μ=10, σ=0.5 (low variance, leads by mean)
    # Runner-up:      μ=9,  σ=5   (high variance, straddles critical mean)
    # Critical-path rule takes σ=0.5, wildly UNDERSTATING true σ of max.
    # Clark correctly folds in the runner-up's variance.
    spec = {
      'a' => { mean: 10.0, stdev: 0.5, depends: [] },
      'b' => { mean: 9.0,  stdev: 5.0, depends: [] },
      'd' => { mean: 1.0,  stdev: 0.1, depends: ['a', 'b'] }
    }
    clark = pert_clark_stdev(spec, 'd')
    crit  = pert_critical_path_stdev(spec, 'd')
    mc    = monte_carlo(spec, 'd')

    # Critical-path is biased low — dramatically so in this regime.
    assert(crit < mc,
           "Sanity: critical-path rule underestimates σ when runner-up has high variance")
    assert(mc / crit > 2.0,
           "Sanity: mc/crit > 2 in this asymmetric case, got #{mc / crit}")
    # Clark is not perfect on heavy-asymmetry cases — the operand it
    # approximates as normal after the first merge is strongly skewed —
    # but should be within 10% of MC.
    assert((clark - mc).abs / mc < 0.10,
           "Asymmetric merge: Clark should match MC within 10%, got rel_err=#{(clark - mc).abs / mc}")
  end

  # ─── Well-separated: Clark reduces to critical-path ──────────

  def test_diamond_well_separated_merge_pert_accurate
    # Means differ by >> σ: Clark correction is negligible.
    spec = {
      'a' => { mean: 10.0, stdev: 0.5, depends: [] },
      'b' => { mean: 5.0,  stdev: 0.5, depends: [] },
      'd' => { mean: 1.0,  stdev: 0.1, depends: ['a', 'b'] }
    }
    clark = pert_clark_stdev(spec, 'd')
    crit  = pert_critical_path_stdev(spec, 'd')
    mc    = monte_carlo(spec, 'd')
    assert((clark - crit).abs / crit < 1e-6,
           "Well-separated: Clark should equal critical-path to machine precision, got gap=#{(clark - crit).abs / crit}")
    assert((clark - mc).abs / mc < 0.03,
           "Well-separated: Clark should match MC within 3%, got rel_err=#{(clark - mc).abs / mc}")
  end

end

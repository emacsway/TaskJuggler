#!/usr/bin/env ruby -w
# frozen_string_literal: true
# encoding: UTF-8
#
# = test_EndStdevMonteCarlo.rb -- The TaskJuggler III Project Management Software
#
# Monte Carlo validation of the PERT method-of-moments propagation
# implemented by TaskScenario#endStdevSlots. These tests sample task
# effort from a normal distribution, compute the resulting end-date
# distribution empirically, and compare its standard deviation against
# the PERT estimate.
#
# The tests document three regimes:
#
# 1. CHAIN  — PERT is exact (σ_end = √Σσ_dur²).
# 2. DIAMOND with DOMINANT critical path — the mean of the critical
#    branch exceeds the nearest runner-up by several σ. PERT's
#    critical-path assumption holds well and the estimate matches MC
#    within a few percent.
# 3. DIAMOND with NEAR-CRITICAL merge — two branches with similar
#    means. PERT's critical-path rule takes σ from one branch only;
#    the deviation from the true σ depends on the asymmetry of the
#    branches:
#
#    * Equal means, equal σ on both sides → PERT OVERESTIMATES (the
#      max-of-two-iid-normals distribution has σ ≈ 0.826·σ_branch,
#      less than either branch).
#    * Higher-mean-but-low-σ branch critical, plus a high-σ runner-up
#      → PERT UNDERESTIMATES (real σ pulls in the runner-up's
#      variance when it samples above the critical-path mean).
#
#    Either way, the first-moment critical-path model is approximate
#    at merges. Clark (1961) gives the closed-form correction; it
#    is not implemented here — see the roadmap in the endupper
#    design document.
#
# The simulation operates on an abstract DAG (effort → duration assumed
# linear, single resource at unit rate) to isolate PERT correctness from
# TJ3's calendar arithmetic. This is the same model PERT's formula
# approximates; what varies between PERT and MC is the treatment of
# max-of-normals at merge points.
#

$:.unshift File.join(File.dirname(__FILE__), '..', 'lib') if __FILE__ == $0
$:.unshift File.dirname(__FILE__)

require 'test/unit'

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

  # PERT computation on the abstract model — mirrors TaskScenario#endStdevSlots
  # logic but on the simple spec hash. Used to isolate the algorithm from
  # TJ3's integration.
  def pert_end_stdev(tasks_spec, target)
    memo_mean = {}
    memo_sigma = {}
    compute = lambda do |name|
      return [memo_mean[name], memo_sigma[name]] if memo_mean.key?(name)
      spec = tasks_spec[name]
      if spec[:depends].empty?
        mean = spec[:mean]
        sigma = spec[:stdev]
      else
        pred_stats = spec[:depends].map { |d| compute.call(d) }
        # Critical predecessor: largest mean end. Ties broken by max σ.
        crit = pred_stats.max_by { |m, s| [m, s] }
        start_mean, start_sigma = crit
        mean = start_mean + spec[:mean]
        sigma = Math.sqrt(start_sigma ** 2 + spec[:stdev] ** 2)
      end
      memo_mean[name] = mean
      memo_sigma[name] = sigma
      [mean, sigma]
    end
    compute.call(target)[1]
  end

  # ─── Chain: PERT is exact ────────────────────────────────────

  def test_chain_pert_matches_mc
    # A → B → C. Each mean=10, stdev=2. Expected PERT: σ = √(3·2²) = 2√3 ≈ 3.46.
    spec = {
      'a' => { mean: 10.0, stdev: 2.0, depends: [] },
      'b' => { mean: 10.0, stdev: 2.0, depends: ['a'] },
      'c' => { mean: 10.0, stdev: 2.0, depends: ['b'] }
    }
    pert = pert_end_stdev(spec, 'c')
    mc   = monte_carlo(spec, 'c')
    assert_in_delta(Math.sqrt(3) * 2.0, pert, 1e-9,
                    "PERT formula should be exact for chain: σ = √3·2")
    rel_err = (pert - mc).abs / mc
    assert(rel_err < 0.03,
           "Chain PERT should match MC within 3%, got rel_err=#{rel_err}")
  end

  # ─── Diamond with dominant critical path ─────────────────────

  def test_diamond_dominant_critical_path
    # Three parallel leaves with very different means — the longest
    # dominates by many σ, so critical-path PERT is accurate.
    spec = {
      'a' => { mean: 3.0,  stdev: 0.5, depends: [] },
      'b' => { mean: 5.0,  stdev: 0.5, depends: [] },
      'c' => { mean: 20.0, stdev: 0.5, depends: [] },
      'd' => { mean: 5.0,  stdev: 0.5, depends: ['a', 'b', 'c'] }
    }
    pert = pert_end_stdev(spec, 'd')
    mc   = monte_carlo(spec, 'd')
    rel_err = (pert - mc).abs / mc
    assert(rel_err < 0.05,
           "Dominant-critical-path diamond: PERT should match MC within 5%, got rel_err=#{rel_err}")
  end

  # ─── Diamond with near-critical merge ───────────────────────

  def test_diamond_near_critical_merge_equal_branches_pert_overestimates
    # Two identical branches (equal mean, equal σ). Max-of-two iid
    # normals has σ ≈ 0.826·σ_branch — SMALLER than either branch.
    # PERT returns the full σ of one branch, overestimating the true σ
    # of the merge. This is a conservative bias.
    spec = {
      'a' => { mean: 10.0, stdev: 2.0, depends: [] },
      'b' => { mean: 10.0, stdev: 2.0, depends: [] },
      'd' => { mean: 1.0,  stdev: 0.1, depends: ['a', 'b'] }
    }
    pert = pert_end_stdev(spec, 'd')
    mc   = monte_carlo(spec, 'd')
    assert(pert > mc,
           "PERT should overestimate σ_end at equal-branch merges; got pert=#{pert}, mc=#{mc}")
    # Closed-form ratio for max of two iid N(μ,σ²) is σ_max/σ =
    # √(1 - 1/π) ≈ 0.8256. With σ_d = 0.1, end σ_MC ≈
    # √((0.826·2)² + 0.1²) ≈ 1.656. PERT reports √(2² + 0.1²) ≈ 2.002.
    # Ratio mc/pert ≈ 0.827.
    ratio = mc / pert
    assert(ratio > 0.78 && ratio < 0.88,
           "mc/pert should be near √(1 - 1/π) ≈ 0.826 for equal iid branches, got #{ratio}")
  end

  def test_diamond_near_critical_merge_asymmetric_pert_underestimates
    # Critical branch has smaller σ, near-critical branch has larger σ
    # and nearly-equal mean. The runner-up occasionally samples above
    # the critical path's mean, pulling σ_end UP. PERT, locked onto
    # the mean-critical branch, UNDERESTIMATES true σ.
    spec = {
      'a' => { mean: 10.0, stdev: 0.5, depends: [] },  # critical by mean
      'b' => { mean: 9.0,  stdev: 5.0, depends: [] },  # noisy runner-up
      'd' => { mean: 1.0,  stdev: 0.1, depends: ['a', 'b'] }
    }
    pert = pert_end_stdev(spec, 'd')
    mc   = monte_carlo(spec, 'd')
    assert(pert < mc,
           "PERT should underestimate when a high-σ runner-up straddles the critical-path mean; " \
           "got pert=#{pert}, mc=#{mc}")
    # The underestimation magnitude depends on the σ ratio — for
    # σ_runner_up = 10·σ_critical, MC σ is typically several times PERT σ.
    assert(mc / pert > 2.0,
           "MC/PERT ratio should be > 2 in this highly asymmetric case, got #{mc / pert}")
  end

  # ─── Far-separated merge: PERT is still good ─────────────────

  def test_diamond_well_separated_merge_pert_accurate
    # When means differ by > 4σ, the Clark correction is negligible
    # and PERT is effectively exact.
    spec = {
      'a' => { mean: 10.0, stdev: 0.5, depends: [] },
      'b' => { mean: 5.0,  stdev: 0.5, depends: [] },  # 10·σ below a
      'd' => { mean: 1.0,  stdev: 0.1, depends: ['a', 'b'] }
    }
    pert = pert_end_stdev(spec, 'd')
    mc   = monte_carlo(spec, 'd')
    rel_err = (pert - mc).abs / mc
    assert(rel_err < 0.03,
           "Well-separated merge: PERT should match MC within 3%, got rel_err=#{rel_err}")
  end

end

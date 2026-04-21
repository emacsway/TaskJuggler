#!/usr/bin/env ruby -w
# frozen_string_literal: true
# encoding: UTF-8
#
# = ClarkMerge.rb -- The TaskJuggler III Project Management Software
#
# Moment-matching approximation for the maximum of normal random variables
# (Clark, C.E., "The Greatest of a Finite Set of Random Variables",
# Operations Research 9 (1961), 145-162).
#
# For independent X_1 ~ N(μ_1, σ_1²) and X_2 ~ N(μ_2, σ_2²), Z = max(X_1, X_2)
# has first two moments:
#
#   a     = √(σ_1² + σ_2²)
#   α     = (μ_1 − μ_2) / a
#   E[Z]  = μ_1 Φ(α) + μ_2 Φ(−α) + a φ(α)
#   E[Z²] = (μ_1² + σ_1²) Φ(α) + (μ_2² + σ_2²) Φ(−α) + (μ_1 + μ_2) a φ(α)
#   σ_Z²  = E[Z²] − E[Z]²
#
# For N > 2 operands Clark's method proceeds pairwise: two operands are
# merged into an approximate normal with the computed (μ, σ); the result
# is merged with the third; and so on. The module provides the primitive
# `merge` and the list-reducing `reduce`.
#
# Assumptions / limits of applicability:
#
#   * Operands are taken as independent normals. Correlations from shared
#     upstream predecessors are not modelled.
#   * The re-normalisation after each pairwise merge introduces a
#     compounding approximation. Accuracy against Monte Carlo is typically
#     within ~2% for 2–5 operands and degrades gradually beyond that.
#   * In the limit of well-separated means (|α| >> 1) Clark reduces
#     exactly to the critical-path rule; in the limit of equal means it
#     captures the standard closed-form σ_max/σ = √(1 − 1/π) ≈ 0.826 for
#     iid inputs.
#

class TaskJuggler

  module ClarkMerge

    INV_SQRT_2PI = 1.0 / Math.sqrt(2.0 * Math::PI)
    INV_SQRT_2   = 1.0 / Math.sqrt(2.0)

    # Standard normal PDF φ(x).
    def self.phi(x)
      INV_SQRT_2PI * Math.exp(-0.5 * x * x)
    end

    # Standard normal CDF Φ(x), via Math.erf.
    def self.cdf(x)
      0.5 * (1.0 + Math.erf(x * INV_SQRT_2))
    end

    # Merge two independent normal operands into the first two moments of
    # their maximum. Returns [mean, stdev]. Degenerate cases handled
    # explicitly so the formulas do not divide by zero.
    def self.merge(m1, s1, m2, s2)
      if s1 == 0.0 && s2 == 0.0
        # Both deterministic: max is just the larger, σ = 0.
        return m1 >= m2 ? [m1, 0.0] : [m2, 0.0]
      end

      a       = Math.sqrt(s1 * s1 + s2 * s2)
      alpha   = (m1 - m2) / a
      phi_a   = phi(alpha)
      cdf_p   = cdf(alpha)         # Φ(α)
      cdf_n   = 1.0 - cdf_p        # Φ(−α)

      new_m = m1 * cdf_p + m2 * cdf_n + a * phi_a
      e_z2  = (m1 * m1 + s1 * s1) * cdf_p +
              (m2 * m2 + s2 * s2) * cdf_n +
              (m1 + m2) * a * phi_a
      var   = e_z2 - new_m * new_m
      # Finite-precision arithmetic can yield a tiny negative residue
      # when operands are near-identical; clamp to 0 so √ is real.
      var   = 0.0 if var < 0.0
      [new_m, Math.sqrt(var)]
    end

    # Reduce an enumerable of [mean, stdev] pairs to the first two
    # moments of their maximum by iterative pairwise Clark merging.
    # Returns [mean, stdev].
    #
    # The list is sorted by mean descending before merging so that the
    # accumulator stays anchored near the dominant operand — this
    # minimises the compounding normal-approximation error and makes
    # the result order-insensitive in the regime where one operand
    # dominates.
    def self.reduce(moments)
      raise ArgumentError, 'ClarkMerge.reduce requires a non-empty list' if moments.empty?
      sorted = moments.sort_by { |m, _| -m }
      acc_m, acc_s = sorted.first
      sorted.drop(1).each do |m, s|
        acc_m, acc_s = merge(acc_m, acc_s, m, s)
      end
      [acc_m, acc_s]
    end

  end

end

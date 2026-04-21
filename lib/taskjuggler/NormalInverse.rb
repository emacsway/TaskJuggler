#!/usr/bin/env ruby -w
# frozen_string_literal: true
# encoding: UTF-8
#
# = NormalInverse.rb -- The TaskJuggler III Project Management Software
#
# Inverse of the standard normal cumulative distribution function Φ⁻¹(p).
#
# Implements the Beasley-Springer-Moro rational approximation
# (Moro, B., "The Full Monte", Risk Magazine 8 (1995), 57-58),
# which combines the Beasley-Springer (1977) central expansion with a
# higher-order tail expansion. Absolute accuracy is better than ~3e-9 in
# the central region and better than ~1e-7 in the tails.
#

class TaskJuggler

  # Standard normal inverse CDF: given a probability p ∈ [0, 1], returns k
  # such that Φ(k) = p, where Φ is the CDF of the standard normal
  # distribution N(0, 1).
  #
  # Used by the `percentile` column option of `endupper` to convert a
  # probability into a σ-multiplier: `sigma = Φ⁻¹(percentile)`.
  module NormalInverse

    # Central region coefficients (Beasley-Springer, 1977).
    A = [
       2.50662823884,
      -18.61500062529,
       41.39119773534,
      -25.44106049637
    ].freeze

    B = [
      -8.47351093090,
       23.08336743743,
      -21.06224101826,
        3.13082909833
    ].freeze

    # Tail region coefficients (Moro, 1995).
    C = [
      0.3374754822726147,
      0.9761690190917186,
      0.1607979714918209,
      0.0276438810333863,
      0.0038405729373609,
      0.0003951896511919,
      0.0000321767881768,
      0.0000002888167364,
      0.0000003960315187
    ].freeze

    # Threshold separating central and tail expansions.
    SPLIT = 0.42

    # Return Φ⁻¹(p), the value k such that the standard normal CDF at k
    # equals p.
    #
    # @param p [Numeric] probability in [0, 1]
    # @return [Float] the corresponding quantile; -Infinity for p == 0,
    #   +Infinity for p == 1
    # @raise [ArgumentError] if p is outside [0, 1]
    def self.ppf(p)
      unless p.is_a?(Numeric) && p >= 0.0 && p <= 1.0
        raise ArgumentError, "NormalInverse.ppf: p must be in [0, 1], got #{p.inspect}"
      end
      return -Float::INFINITY if p == 0.0
      return  Float::INFINITY if p == 1.0

      u = p - 0.5
      if u.abs <= SPLIT
        # Central region: Beasley-Springer rational approximation in y = u².
        y = u * u
        num = ((A[3] * y + A[2]) * y + A[1]) * y + A[0]
        den = (((B[3] * y + B[2]) * y + B[1]) * y + B[0]) * y + 1.0
        u * num / den
      else
        # Tail region: Moro's log-log expansion.
        r = p > 0.5 ? 1.0 - p : p
        z = Math.log(-Math.log(r))
        x = C[8]
        (7).downto(0) { |i| x = x * z + C[i] }
        p > 0.5 ? x : -x
      end
    end

  end

end

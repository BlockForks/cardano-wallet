{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}

module Cardano.Numeric.Util
    ( padCoalesce
    , partitionNatural
    ) where

import Prelude hiding
    ( round )

import Control.Arrow
    ( (&&&) )
import Data.Function
    ( (&) )
import Data.List.NonEmpty
    ( NonEmpty (..) )
import Data.Ord
    ( Down (..), comparing )
import Data.Ratio
    ( (%) )
import Numeric.Natural
    ( Natural )

import qualified Data.Foldable as F
import qualified Data.List.NonEmpty as NE

--------------------------------------------------------------------------------
-- Public functions
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- Coalescing values
--------------------------------------------------------------------------------

-- | Adjusts the source list so that its length is the same as the target list,
--   either by padding the list, or by coalescing a subset of the elements,
--   while preserving the total sum.
--
-- If the source list is shorter than the target list, this function repeatedly
-- inserts 'mempty' into the list until the desired length has been reached.
--
-- If the source list is longer than the target list, this function repeatedly
-- coalesces the smallest pair of elements with '<>' until the desired length
-- has been reached.
--
-- The resulting list is guaranteed to be sorted into ascending order, and the
-- sum of the elements is guaranteed to be the same as the sum of elements in
-- the source list.
--
-- Examples (shown with ordinary list notation):
--
-- >>> padCoalesce [Sum 1] (replicate 4 ())
-- [Sum 0, Sum 0, Sum 0, Sum 1]
--
-- >>> padCoalesce [Sum (-1)] (replicate 4 ())
-- [Sum (-1), Sum 0, Sum 0, Sum 0]
--
-- >>> padCoalesce [Sum 8, Sum 4, Sum 2, Sum 1] (replicate 3 ())
-- [Sum 3, Sum 4, Sum 8]
--
-- >>> padCoalesce [Sum 8, Sum 4, Sum 2, Sum 1] (replicate 2 ())
-- [Sum 7, Sum 8]
--
-- >>> padCoalesce [Sum 8, Sum 4, Sum 2, Sum 1] (replicate 1 ())
-- [Sum 15]
--
padCoalesce :: forall m a. (Monoid m, Ord m)
    => NonEmpty m
    -- ^ Source list
    -> NonEmpty a
    -- ^ Target list
    -> NonEmpty m
padCoalesce sourceUnsorted target
    | sourceLength < targetLength =
        applyN (targetLength - sourceLength) pad source
    | sourceLength > targetLength =
        applyN (sourceLength - targetLength) coalesce source
    | otherwise =
        source
  where
    source = NE.sort sourceUnsorted

    sourceLength = NE.length source
    targetLength = NE.length target

    pad :: NonEmpty m -> NonEmpty m
    pad = NE.insert mempty

    coalesce :: NonEmpty m -> NonEmpty m
    coalesce (x :| y : zs) = NE.insert (x <> y) zs
    coalesce xs = xs

--------------------------------------------------------------------------------
-- Partitioning natural numbers
--------------------------------------------------------------------------------

-- | Partitions a natural number into a number of parts, where the size of each
--   part is proportional to the size of its corresponding element in the given
--   list of weights, and the number of parts is equal to the number of weights.
--
-- Examples:
--
--      >>> partitionNatural 9 (1 :| [1, 1])
--      Just (3 :| [3, 3])
--
--      >>> partitionNatural 10 (1 :| [])
--      10
--
--      >>> partitionNatural 30 (1 :| [2, 4, 8])
--      Just (2 :| [4, 8, 16])
--
-- Pre-condition: there must be at least one non-zero weight.
--
-- If the pre-condition is not satisfied, this function returns 'Nothing'.
--
-- If the pre-condition is satisfied, this function guarantees that:
--
--  1.  The length of the resulting list is identical to the length of the
--      specified list:
--
--      >>> fmap length (partitionNatural n weights) == Just (length weights)
--
--  2.  The sum of elements in the resulting list is equal to the original
--      natural number:
--
--      >>> fmap sum (partitionNatural n weights) == Just n
--
--  3.  The size of each element in the resulting list is within unity of the
--      ideal proportion.
--
partitionNatural
    :: Natural
        -- ^ Natural number to partition
    -> NonEmpty Natural
        -- ^ List of weights
    -> Maybe (NonEmpty Natural)
partitionNatural target weights
    | totalWeight == 0 = Nothing
    | otherwise = Just portionsRounded
  where
    portionsRounded :: NonEmpty Natural
    portionsRounded
        -- 1. Start with the list of unrounded portions:
        = portionsUnrounded
        -- 2. Attach an index to each portion, so that we can remember the
        --    original order:
        & NE.zip indices
        -- 3. Sort the portions into descending order of their fractional
        --    parts, and then sort each subsequence with equal fractional
        --    parts into descending order of their integral parts:
        & NE.sortBy (comparing (Down . (fractionalPart &&& integralPart) . snd))
        -- 4. Apply pre-computed roundings to each portion:
        & NE.zipWith (fmap . round) roundings
        -- 5. Restore the original order:
        & NE.sortBy (comparing fst)
        -- 6. Strip away the indices:
        & fmap snd
      where
        indices :: NonEmpty Int
        indices = 0 :| [1 ..]

    portionsUnrounded :: NonEmpty Rational
    portionsUnrounded = computeIdealPortion <$> weights
      where
        computeIdealPortion c
            = fromIntegral target
            * fromIntegral c
            % fromIntegral totalWeight

    roundings :: NonEmpty RoundingDirection
    roundings =
        applyN shortfall (NE.cons RoundUp) (NE.repeat RoundDown)
      where
        shortfall
            = fromIntegral target
            - fromIntegral @Integer
                (F.sum $ round RoundDown <$> portionsUnrounded)

    totalWeight :: Natural
    totalWeight = F.sum weights

--------------------------------------------------------------------------------
-- Internal types and functions
--------------------------------------------------------------------------------

-- Apply the same function multiple times to a value.
--
applyN :: Int -> (a -> a) -> a -> a
applyN n f = F.foldr (.) id (replicate n f)

-- Extract the fractional part of a rational number.
--
-- Examples:
--
-- >>> fractionalPart (3 % 2)
-- 1 % 2
--
-- >>> fractionalPart (11 % 10)
-- 1 % 10
--
fractionalPart :: Rational -> Rational
fractionalPart = snd . properFraction @_ @Integer

integralPart :: Rational -> Integer
integralPart = floor

-- | Indicates a rounding direction to be used when converting from a
--   fractional value to an integral value.
--
-- See 'round'.
--
data RoundingDirection
    = RoundUp
      -- ^ Round up to the nearest integral value.
    | RoundDown
      -- ^ Round down to the nearest integral value.
    deriving (Eq, Show)

-- | Use the given rounding direction to round the given fractional value,
--   producing an integral result.
--
round :: (RealFrac a, Integral b) => RoundingDirection -> a -> b
round = \case
    RoundUp -> ceiling
    RoundDown -> floor

-- | Field mapping into memory
module ViperVM.Platform.Memory.Layout
   ( Layout(..)
   , FieldPath(..)
   , ScalarField(..)
   , Sign(..)
   , IntBits(..)
   , SizeOf(..)
   , packedSizeOf
   , lookupPath
   , fieldOffset
   , layoutCoveringShape
   )
where

import Prelude hiding (sum)
import Data.Word
import Data.Foldable (sum)
import qualified Data.Vector as V
import Control.Applicative ((<$>))
import ViperVM.Arch.Common.Endianness
import ViperVM.Platform.Memory.Region

-- | A deterministic hierarchic map of fields in memory
--
-- We say it is deterministic because we do not support unions or other
-- data-dependent types, contrary to C structures for examples.
data Layout = 
     Scalar ScalarField          -- ^ Scalar field
   | Array Layout ArraySize      -- ^ Array with determined size
   | Struct (V.Vector Layout)    -- ^ Regular structure; the order of the list of fields matters
   | Padding Word64              -- ^ Padding bytes (i.e. interleaved bytes that have no meaning 
                                 --   for the considered data)
   deriving (Show)

-- | Path to select a field in a field map
newtype FieldPath = FieldPath [Word64]

-- | Size of an array in cells
type ArraySize = Word64

-- | Sign of an integer
data Sign
   = Signed 
   | Unsigned
   deriving (Show)

-- | Number of bits representing an integral field
data IntBits
   = Bit8 
   | Bit16 
   | Bit32 
   | Bit64
   deriving (Show)

-- | Scalar field
data ScalarField =
     IntField Sign IntBits Endianness  -- ^ Numeric integral field (signed or not)
   | FloatField Endianness             -- ^ Single precision floating-point field (IEEE 754)
   | DoubleField Endianness            -- ^ Double precision floating-point field (IEEE 754)
   deriving (Show)

-- | Data type with a fixed number of bytes to represent it
class SizeOf t where
   sizeOf :: t -> Word64

instance SizeOf ScalarField where
   sizeOf (IntField _ Bit8  _) = 1
   sizeOf (IntField _ Bit16 _) = 2
   sizeOf (IntField _ Bit32 _) = 4
   sizeOf (IntField _ Bit64 _) = 8
   sizeOf (FloatField {})      = 4
   sizeOf (DoubleField {})     = 8

instance SizeOf Layout where
   sizeOf (Scalar x) = sizeOf x
   sizeOf (Padding n) = n
   sizeOf (Array t n) = n * sizeOf t
   sizeOf (Struct ts) = sum $ sizeOf <$> ts

-- | Lookup sub field map according to the given field path
--
-- Field index into array are not taken into account,
-- i.e. lookupPath [0,m] (Struct [Array X n]) will return X for any (n,m)
--
lookupPath :: FieldPath -> Layout -> Layout
lookupPath (FieldPath path) = go path
   where
      go [] dt = dt
      go (x:xs) dt = case dt of
         Struct fs -> go xs (fs V.! fromIntegral x)
         Array ct _ -> go xs ct
         _ -> error "Invalid field path"

-- | Return field offset for the given path in the given field map
fieldOffset :: FieldPath -> Layout -> Word64
fieldOffset (FieldPath path) = go 0 path
   where
      go off [] _ = off
      go off (x:xs) dt = case dt of
         Struct fs -> go off' xs (fs V.! fromIntegral x)
            where off' = off + (sum . fmap sizeOf . V.take (fromIntegral x + 1) $ fs)
         Array ct n 
            | x < n -> go (off + x*sizeOf ct) xs ct
            | otherwise -> error "Invalid array indexing"
         _ -> error "Invalid field path"

-- | Return the size of a field map without padding bytes
packedSizeOf :: Layout -> Word64
packedSizeOf dt = case dt of
   s@(Scalar {}) -> sizeOf s
   Padding _ -> 0
   Array dt' n -> n * packedSizeOf dt'
   Struct dts -> sum (fmap packedSizeOf dts)


-- | Return the smallest covering shape (or 1D region if it is the best solution)
--
-- For now, only the last padding bytes of structures in outermost arrays is
-- deleted to build 2D shapes.
layoutCoveringShape :: Layout -> Shape
layoutCoveringShape d = case d of
   Scalar x  -> Shape1D (sizeOf x)

   Padding _ -> Shape1D 0

   Array s@(Struct {}) n -> reg where
      (useful,padding) = layoutStripStructPadding s
      reg = if padding == 0
         then Shape1D (n * useful)
         else Shape2D n useful padding

   Array t' n -> Shape1D (n * sizeOf t')

   t@(Struct {}) -> Shape1D (fst $ layoutStripStructPadding t)

-- | Return (useful,padding) where `padding` is the number
-- of padding bytes at the end of the structure and `useful`
-- the number of remaining bytes (useful ones and other padding)
layoutStripStructPadding :: Layout -> (Word64,Word64)
layoutStripStructPadding (Struct ts) = (useful,padding)
   where
      (useful,padding) = V.foldr f (0,0) ts
      f (Padding p') (0,p) = (0,p'+p)
      f t (u,p) = (u+sizeOf t, p)
layoutStripStructPadding t = (sizeOf t, 0)
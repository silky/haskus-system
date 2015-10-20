{-# LANGUAGE BangPatterns #-}

module ViperVM.Format.Binary.BitGet
   ( BitGetState(..)
   , newBitGetState
   , skipBits
   , getBits
   , getBitsChecked
   , getBitsBS
   -- * Monadic
   , BitGet
   , BitGetT
   , runBitGet
   , runBitGetT
   , skipBitsM
   , getBitsM
   , getBitsCheckedM
   , changeBitGetOrder
   , withBitGetOrder
   )
where

import Data.Bits
import Data.ByteString (ByteString)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Unsafe as BS
import Foreign.Marshal.Alloc (mallocBytes)
import Foreign.Ptr (plusPtr)
import Foreign.Storable (poke)
import System.IO.Unsafe (unsafePerformIO)
import Control.Monad.State
import Control.Monad.Identity

import ViperVM.Format.Binary.BitOrder
import ViperVM.Format.Binary.BitOps

-- | BitGet state
data BitGetState = BitGetState
   { bitGetStateInput      :: {-# UNPACK #-} !ByteString -- ^ Input
   , bitGetStateBitOffset  :: {-# UNPACK #-} !Int        -- ^ Bit offset (0-7)
   , bitGetStateBitOrder   ::                !BitOrder   -- ^ Bit order
   } deriving (Show)

-- | Create a new BitGetState
newBitGetState :: BitOrder -> ByteString -> BitGetState
newBitGetState bo bs = BitGetState bs 0 bo

-- | Skip the given number of bits from the input
skipBits :: Int -> BitGetState -> BitGetState
skipBits o (BitGetState bs n bo) = BitGetState (BS.unsafeDrop d bs) n' bo
   where
      !o' = (n+o)
      !d  = byteOffset o'
      !n' = bitOffset o'

-- | Skip the given number of bits from the input (monadic version)
skipBitsM :: Monad m => Int -> BitGetT m ()
skipBitsM = modify . skipBits

-- | Extract a range of bits from (ws :: ByteString)
--
-- Constraint: 8 * (length ws -1 ) < o+n <= 8 * length ws
extract :: (Num a, Bits a) => BitOrder -> ByteString -> Int -> Int -> a
extract bo bs o n     
   | n == 0            = zeroBits
   | BS.length bs == 0 = error "Empty ByteString"
   | otherwise         = rev . maskLeastBits n . foldlWithIndex' f 0 $ bs
   where 
      -- BS.foldl' with index
      foldlWithIndex' op b = fst . BS.foldl' g (b,0)
         where g (b',i) w = (op b' w i, (i+1))

      -- 'or' correctly shifted words
      f b w i = b .|. (fromIntegral w `shift` off i)

      -- co-offset
      r = BS.length bs * 8 - (o + n)

      -- shift offset depending on the byte position (0..B.length-1)
      off i = case bo of
         LL -> 8*i - o
         LB -> 8*i - o
         BB -> (BS.length bs -1 - i) * 8 - r
         BL -> (BS.length bs -1 - i) * 8 - r

      -- reverse bits if necessary
      rev = case bo of
         LB -> reverseLeastBits n
         BL -> reverseLeastBits n
         BB -> id
         LL -> id


-- | Read the given number of bits and put the result in a word
getBits :: (Num a, Bits a) => Int -> BitGetState -> a
getBits n (BitGetState bs o bo)
   | n == 0    = 0
   | otherwise = extract bo (BS.unsafeTake nbytes bs) o n
   where nbytes = byteOffset (o+n+7)

-- | Perform some checks before calling getBits
--
-- Check that the number of bits to read is not greater than the first parameter
getBitsChecked :: (Num a, Bits a) => Int -> Int -> BitGetState -> a
getBitsChecked m n s
   | n > m     = error $ "Tried to read more than " ++ show m ++ " bits (" ++ show n ++")"
   | otherwise = getBits n s
{-# INLINE getBitsChecked #-}

-- | Read the given number of bytes and return them in Big-Endian order
--
-- Examples:
--    BB: xxxABCDE FGHIJKLM NOPxxxxx -> ABCDEFGH IJKLMNOP
--    LL: LMNOPxxx DEFGHIJK xxxxxABC -> ABCDEFGH IJKLMNOP
--    BL: xxxPONML KJIHGFED CBAxxxxx -> ABCDEFGH IJKLMNOP
--    LB: EDCBAxxx MLKJIHGF xxxxxPON -> ABCDEFGH IJKLMNOP
getBitsBS :: Int -> BitGetState -> ByteString
getBitsBS n (BitGetState bs o bo) =
   let 
      bs'  = BS.unsafeTake (n+1) bs
      bs'' = BS.unsafeTake n bs
      rev  = BS.map (reverseLeastBits 8)
   in case (o,bo) of
      (0,BB) -> bs''
      (0,LL) -> BS.reverse bs''
      (0,LB) -> rev bs''
      (0,BL) -> rev . BS.reverse $ bs''
      (_,LL) -> getBitsBS n (BitGetState (BS.reverse bs') (8-o) BB)
      (_,BL) -> rev . BS.reverse $ getBitsBS n (BitGetState bs' o BB)
      (_,LB) -> rev . BS.reverse $ getBitsBS n (BitGetState bs' o LL)
      (_,BB) -> unsafePerformIO $ do
         let len = n+1
         ptr <- mallocBytes len
         let f r i = do
               let
                  w  = BS.unsafeIndex bs (len-i)
                  w' = (w `shiftL` o) .|. r
                  r' = w `shiftR` (8-o)
               poke (ptr `plusPtr` (len-i)) w'
               return r'
         foldM_ f 0 [1..len]
         BS.unsafeInit <$> BS.unsafePackMallocCStringLen (ptr,len)




type BitGetT m a = StateT BitGetState m a
type BitGet a    = BitGetT Identity a

runBitGetT :: Monad m => BitOrder -> BitGetT m a -> BS.ByteString -> m a
runBitGetT bo m bs = evalStateT m (newBitGetState bo bs)

runBitGet :: BitOrder -> BitGet a -> BS.ByteString -> a
runBitGet bo m bs = runIdentity (runBitGetT bo m bs)

-- | Read the given number of bits and put the result in a word
getBitsM :: (Num a, Bits a, Monad m) => Int -> BitGetT m a
getBitsM n = do
   v <- gets (getBits n)
   skipBitsM n
   return v

-- | Perform some checks before calling getBitsM
getBitsCheckedM :: (Num a, Bits a, Monad m) => Int -> Int -> BitGetT m a
getBitsCheckedM m n = do
   v <- gets (getBitsChecked m n)
   skipBitsM n
   return v

-- | Change the current bit ordering
--
-- Be careful to change the outer bit ordering (B* to L* or the inverse) only
-- on bytes boundaries! Otherwise, you will read the same bits more than once.
changeBitGetOrder :: Monad m => BitOrder -> BitGetT m ()
changeBitGetOrder bo = modify (\s -> s { bitGetStateBitOrder = bo })

-- | Change the bit ordering for the wrapped BitGet
--
-- Be careful, this function uses changeBitGetOrder internally.
withBitGetOrder :: Monad m => BitOrder -> BitGetT m a -> BitGetT m a
withBitGetOrder bo m = do
   bo' <- gets bitGetStateBitOrder
   changeBitGetOrder bo
   v <- m
   changeBitGetOrder bo'
   return v


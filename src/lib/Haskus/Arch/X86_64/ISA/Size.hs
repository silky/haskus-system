-- | Sizes
module Haskus.Arch.X86_64.ISA.Size
   ( Size(..)
   , AddressSize(..)
   , SizedValue(..)
   , OperandSize(..)
   , getSize
   ) where

import Haskus.Format.Binary.Get
import Haskus.Format.Binary.Word

-- | Size
data Size
   = Size8
   | Size16
   | Size32
   | Size64
   | Size128
   | Size256
   | Size512
   deriving (Show,Eq)

-- | Address size
data AddressSize
   = AddrSize16 
   | AddrSize32 
   | AddrSize64 
   deriving (Show,Eq)

-- | Sized value
data SizedValue
   = SizedValue8  !Word8
   | SizedValue16 !Word16
   | SizedValue32 !Word32
   | SizedValue64 !Word64
   deriving (Show,Eq)

-- | Operand size
data OperandSize
   = OpSize8 
   | OpSize16 
   | OpSize32 
   | OpSize64 
   deriving (Show,Eq)

-- | Read a SizedValue
getSize :: Size -> Get SizedValue
getSize Size8  = SizedValue8  <$> getWord8
getSize Size16 = SizedValue16 <$> getWord16le
getSize Size32 = SizedValue32 <$> getWord32le
getSize Size64 = SizedValue64 <$> getWord64le
getSize s      = error ("getSize: unsupported size: " ++ show s)

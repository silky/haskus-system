{-# LANGUAGE DataKinds #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE LambdaCase #-}

-- | Object
module ViperVM.Arch.Linux.Graphics.Object
   ( Object(..)
   , ObjectType(..)
   , getObjectPropertyCount
   , getObjectProperties
   )
where

import ViperVM.Format.Binary.Word
import ViperVM.Format.Binary.Ptr
import ViperVM.Arch.Linux.Graphics.Controller
import ViperVM.Arch.Linux.Graphics.Connector
import ViperVM.Arch.Linux.Graphics.Encoder
import ViperVM.Arch.Linux.Graphics.FrameBuffer
import ViperVM.Arch.Linux.Graphics.Mode
import ViperVM.Arch.Linux.Graphics.Card
import ViperVM.Arch.Linux.Graphics.Property
import ViperVM.Arch.Linux.Internals.Graphics
import ViperVM.Arch.Linux.ErrorCode
import ViperVM.Arch.Linux.Error
import ViperVM.Arch.Linux.Handle

import ViperVM.Format.Binary.Enum
import ViperVM.Utils.Flow
import ViperVM.System.Sys

import Foreign.Marshal.Array

data ObjectType
   = ObjectController
   | ObjectConnector
   | ObjectEncoder
   | ObjectMode
   | ObjectProperty
   | ObjectFrameBuffer
   | ObjectBlob
   | ObjectPlane
   deriving (Show,Eq,Enum)

instance CEnum ObjectType where
   toCEnum x = case x of
      0xcccccccc -> ObjectController
      0xc0c0c0c0 -> ObjectConnector
      0xe0e0e0e0 -> ObjectEncoder
      0xdededede -> ObjectMode
      0xb0b0b0b0 -> ObjectProperty
      0xfbfbfbfb -> ObjectFrameBuffer
      0xbbbbbbbb -> ObjectBlob
      0xeeeeeeee -> ObjectPlane
      _          -> error "Invalid object type"

   fromCEnum x = case x of
      ObjectController   -> 0xcccccccc 
      ObjectConnector    -> 0xc0c0c0c0 
      ObjectEncoder      -> 0xe0e0e0e0 
      ObjectMode         -> 0xdededede 
      ObjectProperty     -> 0xb0b0b0b0 
      ObjectFrameBuffer  -> 0xfbfbfbfb 
      ObjectBlob         -> 0xbbbbbbbb 
      ObjectPlane        -> 0xeeeeeeee 


class Object a where
   getObjectType :: a -> ObjectType
   getObjectID   :: a -> Word32

instance Object Controller where
   getObjectType _ = ObjectController
   getObjectID x   = y
      where ControllerID y = controllerID x

instance Object Connector where
   getObjectType _ = ObjectConnector
   getObjectID x   = y
      where ConnectorID y = connectorID x

instance Object Encoder where
   getObjectType _ = ObjectEncoder
   getObjectID x   = y
      where EncoderID y = encoderID x

instance Object Mode where
   getObjectType _ = ObjectMode
   getObjectID _   = error "getObjectID unsupported for Mode objects"

instance Object FrameBuffer where
   getObjectType _ = ObjectFrameBuffer
   getObjectID x   = y
      where FrameBufferID y = fbID x


-- | Get object's number of properties
getObjectPropertyCount :: Object o => Handle -> o -> Flow Sys '[Word32, ErrorCode]
getObjectPropertyCount hdl o = do
      sysIO (ioctlGetObjectProperties s hdl)
         >.-.> gopCountProps
   where
      s = StructGetObjectProperties 0 0 0
            (getObjectID o)
            (fromCEnum (getObjectType o))

data InvalidCount = InvalidCount Int
data ObjectNotFound = ObjectNotFound deriving (Show,Eq)

-- | Return object properties
getObjectProperties :: Object o => Handle -> o -> Flow Sys '[[RawProperty],ObjectNotFound,InvalidParam]
getObjectProperties hdl o =
       -- we assume 20 entries is usually enough and we adapt if it isn't. By
       -- using an initial value we avoid a syscall in most cases.
      fixCount go 20
   where
      fixCount f n = f n >%~#> \(InvalidCount n') -> fixCount f n'

      allocaArray' 0 f = f nullPtr
      allocaArray' n f = allocaArray (fromIntegral n) f

      go :: Int -> Flow Sys '[[RawProperty],InvalidCount,InvalidParam,ObjectNotFound]
      go n =
         sysWith (allocaArray' n) $ \(propsPtr :: Ptr Word32) ->
         sysWith (allocaArray' n) $ \(valsPtr :: Ptr Word64) -> do
            let
               s = StructGetObjectProperties 
                     (fromIntegral (ptrToWordPtr propsPtr))
                     (fromIntegral (ptrToWordPtr valsPtr))
                     (fromIntegral n)
                     (getObjectID o)
                     (fromCEnum (getObjectType o))
            getObjectProperties' s
               >.~:> checkCount n
               >.~.> extractProperties

      getObjectProperties' :: StructGetObjectProperties -> Flow Sys '[StructGetObjectProperties,InvalidParam,ObjectNotFound]
      getObjectProperties' s = sysIO (ioctlGetObjectProperties s hdl) >%~#> \case
         EINVAL -> flowSet InvalidParam
         ENOENT -> flowSet ObjectNotFound
         e      -> unhdlErr "getObjectProperties" e

      extractProperties :: StructGetObjectProperties -> Sys [RawProperty]
      extractProperties s = do
         let n        = fromIntegral (gopCountProps s)
             propsPtr :: Ptr Word32
             propsPtr = wordPtrToPtr (fromIntegral (gopPropsPtr s))
             valsPtr :: Ptr Word64
             valsPtr  = wordPtrToPtr (fromIntegral (gopValuesPtr s))
         ps <- sysIO (peekArray n propsPtr)
         vs <- sysIO (peekArray n valsPtr)
         return (zipWith RawProperty ps vs)

      -- check that we have allocated enough entries to store the properties
      checkCount :: Int -> StructGetObjectProperties -> Flow Sys '[StructGetObjectProperties,InvalidCount]
      checkCount n s = do
         let n' = fromIntegral (gopCountProps s)
         if n' > n
            then flowSet (InvalidCount n)
            else flowSet s

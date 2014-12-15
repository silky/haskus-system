{-# LANGUAGE ScopedTypeVariables, GeneralizedNewtypeDeriving #-}
-- | Interface to Linux graphics API
--
-- Linux currently uses KMS/DRM interface
module ViperVM.Arch.Linux.Graphics
   ( Capability(..)
   , CardResources(..)
   , Connector(..)
   , Connection(..)
   , SubPixel(..)
   , ConnectorType(..)
   , ConnectorID
   , FrameBufferID
   , CRTCID
   , EncoderID
   , drmIoctl
   , getCapability
   , getModeResources
   , getConnector
   )
where

import ViperVM.Arch.Linux.Ioctl
import ViperVM.Arch.Linux.ErrorCode
import ViperVM.Arch.Linux.FileDescriptor

import Control.Monad.Trans.Either
import Control.Monad.IO.Class (liftIO)
import Control.Applicative ((<$>), (<*>))
import Control.Monad (liftM2)
import Foreign.Marshal.Array (peekArray, allocaArray)
import Foreign.Storable
import Foreign.Ptr
import Data.Word

-- | IOCTL for DRM is restarted on interruption
-- Apply this function to your preferred ioctl function
drmIoctl :: IOCTL -> IOCTL
drmIoctl = repeatIoctl

data Capability
   = CapDUMMY     -- Added to easily derive Enum (start at 0x01...)
   | CapDumbBuffer
   | CapVBlankHighCRTC
   | CapDumbPreferredDepth
   | CapDumbPreferShadow
   | CapPrime
   | CapTimestampMonotonic
   | CapAsyncPageFlip
   deriving (Show,Eq,Enum)

-- | Parameter for getCapability IOCTL (capability id, return value)
data GetCapability = GetCapability Word64 Word64

instance Storable GetCapability where
   sizeOf _ = 16
   alignment _ = 8
   peek ptr = 
      let p = castPtr ptr :: Ptr Word64 in
         GetCapability <$> peekElemOff p 0 <*> peekElemOff p 1
   poke ptr (GetCapability x y) = do
      let p = castPtr ptr :: Ptr Word64
      pokeElemOff p 0 x
      pokeElemOff p 1 y

-- | Indicate if the given capability is supported
getCapability :: IOCTL -> FileDescriptor -> Capability -> SysRet Word64
getCapability ioctl fd cap = do
   let param = GetCapability (fromIntegral $ fromEnum cap) 0
   ret <- ioctlReadWrite ioctl 0x64 0x0c defaultCheck fd param
   case ret of
      Left err -> return (Left err)
      Right (GetCapability _ value) -> return (Right value)

newtype ConnectorID    = ConnectorID Word32 deriving (Show,Eq,Storable)
newtype FrameBufferID  = FrameBufferID Word32 deriving (Show,Eq,Storable)
newtype CRTCID         = CRTCID Word32 deriving (Show,Eq,Storable)
newtype EncoderID      = EncoderID Word32 deriving (Show,Eq,Storable)

data CardResources = CardResources
   { framebuffers    :: [FrameBufferID]
   , crtcs           :: [CRTCID]
   , connectors      :: [ConnectorID]
   , encoders        :: [EncoderID]
   , minWidth        :: Word32
   , maxWidth        :: Word32
   , minHeight       :: Word32
   , maxHeight       :: Word32
   } deriving (Show)

-- | Parameter for MODE_GETRESOURCES IOCTL
data ModeCardRes = ModeCardRes
   { fbPtr           :: Word64
   , crtcPtr         :: Word64
   , connectorPtr    :: Word64
   , encoderPtr      :: Word64

   , fbCount         :: Word32
   , crtcCount       :: Word32
   , connectorCount  :: Word32
   , encoderCount    :: Word32

   , minWidth_       :: Word32
   , maxWidth_       :: Word32
   , minHeight_      :: Word32
   , maxHeight_      :: Word32
   } deriving (Show)

instance Storable ModeCardRes where
   sizeOf _    = 4*(8+4) + 4*4
   alignment _ = 8
   peek ptr    = ModeCardRes
      <$> peekByteOff ptr 0
      <*> peekByteOff ptr 8
      <*> peekByteOff ptr 16
      <*> peekByteOff ptr 24
      <*> peekByteOff ptr 32
      <*> peekByteOff ptr 36
      <*> peekByteOff ptr 40
      <*> peekByteOff ptr 44
      <*> peekByteOff ptr 48
      <*> peekByteOff ptr 52
      <*> peekByteOff ptr 56
      <*> peekByteOff ptr 60
   poke ptr res = do
      pokeByteOff ptr 0  (fbPtr           res)
      pokeByteOff ptr 8  (crtcPtr         res)
      pokeByteOff ptr 16 (connectorPtr    res)
      pokeByteOff ptr 24 (encoderPtr      res)
      pokeByteOff ptr 32 (fbCount         res)
      pokeByteOff ptr 36 (crtcCount       res)
      pokeByteOff ptr 40 (connectorCount  res)
      pokeByteOff ptr 44 (encoderCount    res)
      pokeByteOff ptr 48 (minWidth_       res)
      pokeByteOff ptr 52 (maxWidth_       res)
      pokeByteOff ptr 56 (minHeight_      res)
      pokeByteOff ptr 60 (maxHeight_      res)


-- | Get mode resources
--
-- It seems like the kernel fills *Count fields and min/max fields.  If *Ptr
-- fields are not NULL, the kernel fills the pointed arrays with up to *Count
-- elements.
-- 
getModeResources :: IOCTL -> FileDescriptor -> SysRet CardResources
getModeResources ioctl fd = runEitherT $ do
   let 
      res = ModeCardRes 0 0 0 0 0 0 0 0 0 0 0 0
      allocaArray'      = allocaArray . fromIntegral
      peekArray'        = peekArray . fromIntegral
      getModeResources' = EitherT . ioctlReadWrite ioctl 0x64 0xA0 defaultCheck fd

   -- First we get the number of each resource
   res2 <- getModeResources' res

   -- then we allocate arrays of appropriate sizes
   (rawRes, retRes) <-
      EitherT $ allocaArray' (fbCount res2) $ \(fs :: Ptr Word32) ->
         allocaArray'(crtcCount res2) $ \(crs :: Ptr Word32) ->
            allocaArray' (connectorCount res2) $ \(cs:: Ptr Word32) ->
               allocaArray' (encoderCount res2) $ \(es:: Ptr Word32) -> runEitherT $ do
                  -- we put them in a new struct
                  let
                     cv = fromIntegral . ptrToWordPtr
                     res3 = res2 { fbPtr        = cv fs
                                 , crtcPtr      = cv crs
                                 , encoderPtr   = cv es
                                 , connectorPtr = cv cs
                                 }
                  -- we get the values
                  res4 <- getModeResources' res3
                  res5 <- liftIO $ CardResources
                     <$> (fmap FrameBufferID <$> peekArray' (fbCount res2) fs)
                     <*> (fmap CRTCID <$> peekArray' (crtcCount res2) crs)
                     <*> (fmap ConnectorID <$> peekArray' (connectorCount res2) cs)
                     <*> (fmap EncoderID <$> peekArray' (encoderCount res2) es)
                     <*> return (minWidth_ res4)
                     <*> return (maxWidth_ res4)
                     <*> return (minHeight_ res4)
                     <*> return (maxHeight_ res4)

                  right (res4, res5)

   -- we need to check that the number of resources is still the same (a
   -- resources may have appeared between the time we get the number of
   -- resources an the time we get them...)
   -- If not, we redo the whole process
   if   fbCount        res2 < fbCount        rawRes
     || crtcCount      res2 < crtcCount      rawRes
     || connectorCount res2 < connectorCount rawRes
     || encoderCount   res2 < encoderCount   rawRes
      then EitherT $ getModeResources ioctl fd
      else right retRes


data ModeGetConnector = ModeGetConnector
   { connEncodersPtr       :: Word64
   , connModesPtr          :: Word64
   , connPropsPtr          :: Word64
   , connPropValuesPtr     :: Word64

   , connModesCount        :: Word32
   , connPropsCount        :: Word32
   , connEncodersCount     :: Word32

   , connEncoderID_        :: Word32   -- ^ current encoder
   , connConnectorID_      :: Word32   -- ^ ID
   , connConnectorType_    :: Word32
   , connConnectorTypeID_  :: Word32

   , connConnection_       :: Word32
   , connWidth_            :: Word32   -- ^ HxW in millimeters
   , connHeight_           :: Word32
   , connSubPixel_         :: Word32
   } deriving (Show)

instance Storable ModeGetConnector where
   sizeOf _    = 4*8 + (3+4+4)*4
   alignment _ = 8
   peek ptr    = ModeGetConnector
      <$> peekByteOff ptr 0
      <*> peekByteOff ptr 8
      <*> peekByteOff ptr 16
      <*> peekByteOff ptr 24

      <*> peekByteOff ptr 32
      <*> peekByteOff ptr 36
      <*> peekByteOff ptr 40

      <*> peekByteOff ptr 44
      <*> peekByteOff ptr 48
      <*> peekByteOff ptr 52
      <*> peekByteOff ptr 56

      <*> peekByteOff ptr 60
      <*> peekByteOff ptr 64
      <*> peekByteOff ptr 68
      <*> peekByteOff ptr 72
   poke ptr res = do
      pokeByteOff ptr 0  (connEncodersPtr       res)
      pokeByteOff ptr 8  (connModesPtr          res)
      pokeByteOff ptr 16 (connPropsPtr          res)
      pokeByteOff ptr 24 (connPropValuesPtr     res)

      pokeByteOff ptr 32 (connModesCount        res)
      pokeByteOff ptr 36 (connPropsCount        res)
      pokeByteOff ptr 40 (connEncodersCount     res)

      pokeByteOff ptr 44 (connEncoderID_        res)
      pokeByteOff ptr 48 (connConnectorID_      res)
      pokeByteOff ptr 52 (connConnectorType_    res)
      pokeByteOff ptr 56 (connConnectorTypeID_  res)

      pokeByteOff ptr 60 (connConnection_       res)
      pokeByteOff ptr 64 (connWidth_            res)
      pokeByteOff ptr 68 (connHeight_           res)
      pokeByteOff ptr 72 (connSubPixel_         res)

newtype ModeID = ModeID Word32 deriving (Show)
data ConnectorProperty = ConnectorProperty Word32 Word64 deriving (Show)

data ConnectorType
   = ConnectorTypeUnknown
   | ConnectorTypeVGA
   | ConnectorTypeDVII
   | ConnectorTypeDVID
   | ConnectorTypeDVIA
   | ConnectorTypeComposite
   | ConnectorTypeSVIDEO
   | ConnectorTypeLVDS
   | ConnectorTypeComponent
   | ConnectorType9PinDIN
   | ConnectorTypeDisplayPort
   | ConnectorTypeHDMIA
   | ConnectorTypeHDMIB
   | ConnectorTypeTV
   | ConnectorTypeeDP
   | ConnectorTypeVirtual
   | ConnectorTypeDSI
   deriving (Eq, Ord, Enum)

instance Show ConnectorType where
   show x = case x of
      ConnectorTypeUnknown       -> "Unknown"
      ConnectorTypeVGA           -> "VGA"
      ConnectorTypeDVII          -> "DVI-I"
      ConnectorTypeDVID          -> "DVI-D"
      ConnectorTypeDVIA          -> "DVI-A"
      ConnectorTypeComposite     -> "Composite"
      ConnectorTypeSVIDEO        -> "SVIDEO"
      ConnectorTypeLVDS          -> "LVDS"
      ConnectorTypeComponent     -> "Component"
      ConnectorType9PinDIN       -> "9PinDIN"
      ConnectorTypeDisplayPort   -> "DisplayPort"
      ConnectorTypeHDMIA         -> "HDMI-A"
      ConnectorTypeHDMIB         -> "HDMI-B"
      ConnectorTypeTV            -> "TV"
      ConnectorTypeeDP           -> "eDP"
      ConnectorTypeVirtual       -> "Virtual"
      ConnectorTypeDSI           -> "DSI"

newtype ConnectorTypeID = ConnectorTypeID Word32 deriving (Show)


data Connection
   = Connected
   | Disconnected
   | ConnectionUnknown
   deriving (Eq,Ord,Show)

data SubPixel
   = SubPixelUnknown
   | SubPixelHorizontalRGB
   | SubPixelHorizontalBGR
   | SubPixelVerticalRGB
   | SubPixelVerticalBGR
   | SubPixelNone
   deriving (Eq,Ord,Enum,Show)

data Connector = Connector
   { connEncoders          :: [EncoderID]
   , connModes             :: [ModeID]
   , connProperties        :: [ConnectorProperty]
   , connEncoderID         :: EncoderID
   , connConnectorID       :: ConnectorID
   , connConnectorType     :: ConnectorType
   , connConnectorTypeID   :: ConnectorTypeID

   , connConnection        :: Connection
   , connWidth             :: Word32   -- ^ HxW in millimeters
   , connHeight            :: Word32
   , connSubPixel          :: SubPixel
   } deriving (Show)


-- | Get connector
getConnector :: IOCTL -> FileDescriptor -> ConnectorID -> SysRet Connector
getConnector ioctl fd connId@(ConnectorID cid) = runEitherT $ do
   let 
      res = ModeGetConnector 0 0 0 0 0 0 0 0 cid 0 0 0 0 0 0

      allocaArray' :: (Integral c, Storable a) => c -> (Ptr a -> IO b) -> IO b
      allocaArray'      = allocaArray . fromIntegral

      peekArray' :: (Storable a, Integral c) => c -> Ptr a -> IO [a]
      peekArray'        = peekArray . fromIntegral

      getModeConnector' = EitherT . ioctlReadWrite ioctl 0x64 0xA7 defaultCheck fd

   -- First we get the number of each resource
   res2 <- getModeConnector' res

   -- then we allocate arrays of appropriate sizes
   (rawRes, retRes) <-
      EitherT $ allocaArray' (connModesCount res2) $ \(ms :: Ptr Word32) ->
         allocaArray' (connPropsCount res2) $ \(ps :: Ptr Word32) ->
            allocaArray' (connPropsCount res2) $ \(pvs :: Ptr Word64) ->
               allocaArray' (connEncodersCount res2) $ \(es:: Ptr Word32) -> runEitherT $ do
                  -- we put them in a new struct
                  let
                     cv = fromIntegral . ptrToWordPtr
                     res3 = res2 { connEncodersPtr   = cv es
                                 , connModesPtr      = cv ms
                                 , connPropsPtr      = cv ps
                                 , connPropValuesPtr = cv pvs
                                 }
                     isConnected x = case x of
                        1 -> Connected
                        2 -> Disconnected
                        _ -> ConnectionUnknown

                  -- we get the values
                  res4 <- getModeConnector' res3
                  res5 <- liftIO $ Connector
                     <$> (fmap EncoderID <$> peekArray' (connEncodersCount res2) es)
                     <*> (fmap ModeID <$> peekArray' (connModesCount res2) ms)
                     <*> (liftM2 ConnectorProperty <$> peekArray' (connPropsCount res2) ps
                                                   <*> peekArray' (connPropsCount res2) pvs)
                     <*> return (EncoderID             $ connEncoderID_ res4)
                     <*> return (ConnectorID           $ connConnectorID_ res4)
                     <*> return (toEnum . fromIntegral $ connConnectorType_ res4)
                     <*> return (ConnectorTypeID       $ connConnectorTypeID_ res4)
                     <*> return (isConnected           $ connConnection_ res4)
                     <*> return (connWidth_ res4)
                     <*> return (connHeight_ res4)
                     <*> return (toEnum . fromIntegral $ connSubPixel_ res4)

                  right (res4, res5)

   -- we need to check that the number of resources is still the same (a
   -- resources may have appeared between the time we get the number of
   -- resources an the time we get them...)
   -- If not, we redo the whole process
   if   connModesCount    res2 < connModesCount    rawRes
     || connPropsCount    res2 < connPropsCount    rawRes
     || connEncodersCount res2 < connEncodersCount rawRes
      then EitherT $ getConnector ioctl fd connId
      else right retRes

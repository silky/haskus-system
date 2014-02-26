module ViperVM.Platform.OpenCL.CommandQueue (
   CommandQueue, CommandQueueProperty(..),
   CommandType, CommandExecutionStatus,
   ProfilingInfo, CommandQueueInfo,
   createCommandQueue,
   flush, finish, enqueueBarrier
) where

import ViperVM.Platform.OpenCL.Entity
import ViperVM.Platform.OpenCL.Library
import ViperVM.Platform.OpenCL.Types
import ViperVM.Platform.OpenCL.Bindings
import ViperVM.Platform.OpenCL.Error
import ViperVM.Platform.OpenCL.Context
import ViperVM.Platform.OpenCL.Device

import Control.Applicative ((<$>))
import Control.Monad (void)

data CommandQueue = CommandQueue Library CommandQueue_ deriving (Eq)

instance Entity CommandQueue where 
   unwrap (CommandQueue _ x) = x
   cllib (CommandQueue l _) = l
   retain = retainCommandQueue
   release = releaseCommandQueue

data CommandQueueProperty =
     CL_QUEUE_OUT_OF_ORDER_EXEC_MODE_ENABLE
   | CL_QUEUE_PROFILING_ENABLE
   deriving (Show, Bounded, Eq, Ord, Enum)

instance CLSet CommandQueueProperty

data CommandType =
     CL_COMMAND_NDRANGE_KERNEL      
   | CL_COMMAND_TASK                
   | CL_COMMAND_NATIVE_KERNEL       
   | CL_COMMAND_READ_BUFFER         
   | CL_COMMAND_WRITE_BUFFER        
   | CL_COMMAND_COPY_BUFFER         
   | CL_COMMAND_READ_IMAGE          
   | CL_COMMAND_WRITE_IMAGE         
   | CL_COMMAND_COPY_IMAGE          
   | CL_COMMAND_COPY_IMAGE_TO_BUFFER
   | CL_COMMAND_COPY_BUFFER_TO_IMAGE
   | CL_COMMAND_MAP_BUFFER          
   | CL_COMMAND_MAP_IMAGE           
   | CL_COMMAND_UNMAP_MEM_OBJECT    
   | CL_COMMAND_MARKER              
   | CL_COMMAND_ACQUIRE_GL_OBJECTS  
   | CL_COMMAND_RELEASE_GL_OBJECTS  
   | CL_COMMAND_READ_BUFFER_RECT    
   | CL_COMMAND_WRITE_BUFFER_RECT   
   | CL_COMMAND_COPY_BUFFER_RECT    
   | CL_COMMAND_USER                
   | CL_COMMAND_BARRIER             
   | CL_COMMAND_MIGRATE_MEM_OBJECTS 
   | CL_COMMAND_FILL_BUFFER         
   | CL_COMMAND_FILL_IMAGE          
   deriving (Show,Enum)

instance CLConstant CommandType where
   toCL x = fromIntegral (fromEnum x + 0x11F0)
   fromCL x = toEnum (fromIntegral x - 0x11F0)

data CommandExecutionStatus =
     CL_EXEC_ERROR   -- -1
   | CL_COMPLETE     -- 0
   | CL_RUNNING      -- 1
   | CL_SUBMITTED    -- 2
   | CL_QUEUED       -- 3
   deriving (Show,Enum)

instance CLConstant CommandExecutionStatus where
   toCL x = fromIntegral (fromEnum x - 1)
   fromCL x = toEnum (fromIntegral x + 1)

data ProfilingInfo =
     CL_PROFILING_COMMAND_QUEUED
   | CL_PROFILING_COMMAND_SUBMIT
   | CL_PROFILING_COMMAND_START
   | CL_PROFILING_COMMAND_END
   deriving (Show,Enum)

instance CLConstant ProfilingInfo where
   toCL x = fromIntegral (fromEnum x + 0x1280)
   fromCL x = toEnum (fromIntegral x - 0x1280)

data CommandQueueInfo = 
     CL_QUEUE_CONTEXT 
   | CL_QUEUE_DEVICE
   | CL_QUEUE_REFERENCE_COUNT
   | CL_QUEUE_PROPERTIES
   deriving (Enum)

instance CLConstant CommandQueueInfo where
   toCL x = fromIntegral (fromEnum x + 0x1090)
   fromCL x = toEnum (fromIntegral x - 0x1090)


-- | Create a command queue
createCommandQueue :: Context -> Device -> [CommandQueueProperty] -> IO (Either CLError CommandQueue)
createCommandQueue ctx dev props =
   fmap (CommandQueue lib) <$> wrapPError (rawClCreateCommandQueue lib (unwrap ctx) (unwrap dev) (toCLSet props))
   where lib = cllib ctx

-- | Release a command queue
releaseCommandQueue :: CommandQueue -> IO ()
releaseCommandQueue cq = void (rawClReleaseCommandQueue (cllib cq) (unwrap cq))

-- | Retain a command queue
retainCommandQueue :: CommandQueue -> IO ()
retainCommandQueue cq = void (rawClRetainCommandQueue (cllib cq) (unwrap cq))

-- | Flush commands
flush :: CommandQueue -> IO CLError
flush cq = fromCL <$> rawClFlush (cllib cq) (unwrap cq)

-- | Finish commands
finish :: CommandQueue -> IO CLError
finish cq = fromCL <$> rawClFinish (cllib cq) (unwrap cq)

-- | Enqueue barrier
enqueueBarrier :: CommandQueue -> IO CLError
enqueueBarrier cq = fromCL <$> rawClEnqueueBarrier (cllib cq) (unwrap cq)

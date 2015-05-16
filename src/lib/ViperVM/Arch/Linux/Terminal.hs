-- | This module provides some functions to use Linux
-- terminals
module ViperVM.Arch.Linux.Terminal
   ( stdin
   , stdout
   , stderr
   , writeStr
   , writeStrLn
   )
   where

import ViperVM.Arch.Linux.ErrorCode
import ViperVM.Arch.Linux.FileSystem.ReadWrite
import ViperVM.Arch.Linux.FileDescriptor

import qualified Data.ByteString.Char8 as BS
import Data.Word

-- | Standard input (by convention)
stdin :: FileDescriptor
stdin = FileDescriptor 0

-- | Standard output (by convention)
stdout :: FileDescriptor
stdout = FileDescriptor 1

-- | Standard error output (by convention)
stderr :: FileDescriptor
stderr = FileDescriptor 2

-- | Write a String in the given file descriptor
writeStr :: FileDescriptor -> String -> SysRet Word64
writeStr fd = writeByteString fd . BS.pack

-- | Write a String with a newline character in the given
-- file descriptor
writeStrLn :: FileDescriptor -> String -> SysRet Word64
writeStrLn fd = writeByteString fd . BS.pack . (++ "\n")
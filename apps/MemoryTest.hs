import Control.Monad (forM)
import Control.Monad ((<=<))
import Control.Applicative ((<$>))
import Data.Foldable (traverse_)

import ViperVM.Platform.Platform
import ViperVM.Platform.PlatformInfo
import ViperVM.Platform.Config
import ViperVM.Platform.Loading
import ViperVM.Platform.Memory.Layout
import ViperVM.Platform.Memory.Manager

main :: IO ()
main = do
   putStrLn "Loading Platform..."
   pf <- loadPlatform defaultConfig

   traverse_ (putStrLn <=< memoryInfo) (platformMemories pf)

   putStrLn "\nCreate basic memory manager for each memory"
   mgrs <- forM (platformMemories pf) (initManager defaultManagerConfig)

   putStrLn "\nAllocating data in each memory"
   datas <- forM mgrs $ \mgr -> do
      let 
         dt = \endian -> Array (Scalar (DoubleField endian)) 128
         f = either (error . ("Allocation error: " ++) . show) id
      
      f <$> allocateDataWithEndianness dt mgr

   traverse_ (putStrLn <=< memoryInfo) (platformMemories pf)

   putStrLn "\nReleasing data in each memory"
   traverse_ (uncurry releaseData) (mgrs `zip` datas)

   traverse_ (putStrLn <=< memoryInfo) (platformMemories pf)

   putStrLn "Done."

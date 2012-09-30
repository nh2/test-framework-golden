{- |
This module provides a simplified interface. If you want more, see
  "Test.Framework.Providers.Golden.Advanced"
-}
module Test.Framework.Providers.Golden
  ( goldenVsFile
  , goldenVsString
  , goldenVsFileDiff
  )
  where

import Test.Framework.Providers.API
import Test.Framework.Providers.Golden.Advanced
import Text.Printf
import Data.Maybe
import qualified Data.ByteString.Lazy as LB
import System.IO
import System.Process
import System.Exit
import Control.Exception

-- | Compare a given file contents against the golden file contents
goldenVsFile
  :: TestName -- ^ test name
  -> FilePath -- ^ path to the «golden» file (the file that contains correct output)
  -> FilePath -- ^ path to the output file
  -> IO () -- ^ action that creates the output file
  -> Test -- ^ the test verifies that the output file contents is the same as the golden file contents
goldenVsFile name ref new act =
  goldenTest
    name
    (vgReadFile showLit ref)
    (vgLiftIO act >> vgReadFile showLit new)
    cmp
    upd
  where
  cmp = simpleCmp $ Lit $ printf "Files '%s' and '%s' differ" ref new
  upd = LB.writeFile ref

-- | Compare a given string against the golden file contents
goldenVsString
  :: TestName -- ^ test name
  -> FilePath -- ^ path to the «golden» file (the file that contains correct output)
  -> IO LB.ByteString -- ^ action that returns a string
  -> Test -- ^ the test verifies that the returned string is the same as the golden file contents
goldenVsString name ref act =
  goldenTest
    name
    (vgReadFile showLit ref)
    (vgLiftIO act)
    cmp
    upd
  where
  cmp x y = simpleCmp msg x y
    where
    msg = Lit $ printf "Test output was different from '%s'. It was: %s" ref (show y)
  upd = LB.writeFile ref

simpleCmp :: Eq a => Lit -> a -> a -> IO (Maybe Lit)
simpleCmp e x y =
  return $ if x == y then Nothing else Just e

goldenVsFileDiff
  :: TestName -- ^ test name
  -> (FilePath -> FilePath -> [String])
    -- ^ function that constructs the command line to invoke the diff
    -- command
  -> FilePath -- ^ path to the golden file
  -> FilePath -- ^ path to the output file
  -> IO ()    -- ^ action that produces the output file
  -> Test
goldenVsFileDiff name cmdf ref new act =
  goldenTest
    name
    (return ())
    (vgLiftIO act)
    cmp
    upd
  where
  cmd = cmdf ref new
  cmp _ _ | null cmd = error "goldenVsFileDiff: empty command line"
  cmp _ _ = do
    (_, Just sout, _, pid) <- createProcess (proc (head cmd) (tail cmd)) { std_out = CreatePipe }
    -- strictly read the whole output, so that the process can terminate
    out <- hGetContents sout
    evaluate $ length out

    r <- waitForProcess pid
    return $ case r of
      ExitSuccess -> Nothing
      _ -> Just $ Lit out

  upd _ = LB.readFile new >>= LB.writeFile ref

{-# LANGUAGE GeneralizedNewtypeDeriving, PatternGuards #-}
-- | Use functions from this module instead of
-- "Test.Framework.Runners.Console" to enable golden test management
-- options.
module Test.Golden.Console (defaultMain, defaultMainWithArgs) where

import Test.Framework hiding (defaultMain, defaultMainWithArgs)
import Test.Framework.Runners.API
import qualified Test.Framework.Runners.Console as TF
import System.Console.GetOpt
import System.IO
import System.Environment
import Test.Golden.Internal
import Data.Monoid
import Data.Maybe
import Data.Typeable
import Data.Either
import Control.Applicative
import Control.Monad.Cont
import Control.Exception
import Text.Printf

newtype TestList = TestList { testList :: IO [(TestName, Golden)] }

instance Monoid TestList where
  mempty = TestList $ return []
  TestList a `mappend` TestList b =
    TestList $ mappend <$> a <*> b

instance TestRunner TestList where
  runSimpleTest _opts name test =
    TestList $ return $ fmap ((,) name) $ maybeToList $ cast test

  skipTest = mempty

  runIOTest = mempty

  runGroup _ = mconcat

getGoldenTests :: [TestPattern] -> Test -> IO [(TestName, Golden)]
getGoldenTests pats = testList . runTestTree mempty pats

acceptGoldenTest :: Golden -> IO (Either SomeException ())
acceptGoldenTest (Golden _ getTested _ update) =
  vgRun $ liftIO . update =<< getTested

data Cmd = Accept

combinedOptions :: [OptDescr (Either Cmd SuppliedRunnerOptions)]
combinedOptions =
  map (fmap Right) optionsDescription ++
  map (fmap Left)
    [ Option [] ["accept"]
        (NoArg Accept)
        "update golden tests (all by default; use -t to specify which ones)"
    ]

defaultMain :: [Test] -> IO ()
defaultMain tests = do
  args <- getArgs
  defaultMainWithArgs tests args

defaultMainWithArgs :: [Test] -> [String] -> IO ()
defaultMainWithArgs tests args = do
  prog_name <- getProgName
  let usage_header = "Usage: " ++ prog_name ++ " [OPTIONS]"

      (opts, _nonopts, errMsgs) = getOpt Permute combinedOptions args

      err = do
        hPutStrLn stderr $
          concat errMsgs ++ usageInfo usage_header combinedOptions

      (ourOpts, tfOptPieces) = partitionEithers opts
      mbTfOpts = mconcat <$> sequence tfOptPieces

  case mbTfOpts of
    Nothing -> err
    Just tfOpts
      | [Accept] <- ourOpts ->
          let pats = fromMaybe [] $ ropt_test_patterns tfOpts
          in doAccept pats tests
      | [] <- ourOpts ->
          TF.defaultMainWithOpts tests tfOpts
    _ -> err

doAccept :: [TestPattern] -> [Test] -> IO ()
doAccept pats tests = do
  gs <- concat <$> mapM (getGoldenTests pats) tests
  forM_ gs $ \(n,g) -> do
    r <- acceptGoldenTest g
    case r of
      Right {} -> printf "Accepted %s\n" n
      Left e -> printf "Failed to update %s: %s\n" n (show e)

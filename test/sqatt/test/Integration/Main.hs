{-
TorXakis - Model Based Testing
Copyright (c) 2015-2017 TNO and Radboud University
See LICENSE at root directory of this repository.
-}
{-# LANGUAGE OverloadedStrings #-}
import           Integration.All
import           Sqatt           hiding (parallel)
import           Test.Hspec

main :: IO ()
main = do
    logDir <- mkLogDir "integration-test-"
    --parallel causes nondeterministic crashes. Removed until it can be fixed.
    --hspec $ parallel $ testExampleSets logDir allTests
    hspec  $ testExampleSets logDir allTests


{-
TorXakis - Model Based Testing
Copyright (c) 2015-2017 TNO and Radboud University
See LICENSE at root directory of this repository.
-}
{-# LANGUAGE TemplateHaskell #-}
module BuildInfo
where
import Language.Haskell.TH.Syntax 
import Data.Time.Clock 
import Data.Time 
import Control.Applicative
-- The time this file was last build as a string. Format is <Dayname Day/Month/Year Hour:Minutes:Secons>
buildTime :: String
buildTime = $(runIO (fmap (formatTime defaultTimeLocale "%a %d/%m/%Y %T") (liftA2 utcToLocalTime getCurrentTimeZone getCurrentTime))  >>= lift)
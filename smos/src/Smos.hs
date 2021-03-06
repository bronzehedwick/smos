{-# LANGUAGE RecordWildCards #-}

module Smos
    ( smos
    , module Smos.Config
    ) where

import Import

import Data.Time

import Control.Concurrent
import Control.Concurrent.Async
import System.Exit

import Brick.BChan as Brick
import Brick.Main as Brick
import Graphics.Vty as Vty (defaultConfig, mkVty)

import Smos.Data

import Smos.App
import Smos.Config
import Smos.OptParse
import Smos.Types

smos :: SmosConfig -> IO ()
smos sc@SmosConfig {..} = do
    Instructions p Settings <- getInstructions sc
    lock <- lockFile p
    case lock of
        Nothing -> die "Failed to lock."
        Just fl -> do
            errOrSF <- readSmosFile p
            startF <-
                case errOrSF of
                    Nothing -> pure Nothing
                    Just (Left err) ->
                        die $
                        unlines
                            [ "Failed to read smos file"
                            , fromAbsFile p
                            , "could not parse it:"
                            , show err
                            ]
                    Just (Right sf) -> pure $ Just sf
            zt <- getZonedTime
            let s = initState zt p fl startF
            chan <- Brick.newBChan maxBound
            Left s' <-
                race
                    (Brick.customMain
                         (Vty.mkVty Vty.defaultConfig)
                         (Just chan)
                         (mkSmosApp sc)
                         s)
                    (eventPusher chan)
            let sf' = rebuildEditorCursor $ smosStateCursor s'
            let p' = smosStateFilePath s'
            (case smosStateStartSmosFile s' of
                 Nothing -> unless (sf' == emptySmosFile)
                 Just sf'' -> unless (sf'' == sf')) $
                writeSmosFile p' sf'
            unlockFile $ smosStateFileLock s'

eventPusher :: BChan SmosEvent -> IO ()
eventPusher chan =
    concurrently_
        (loopEvery 1 (writeBChan chan SmosUpdateTime))
        (loopEvery 2 (writeBChan chan SmosSaveFile))
  where
    loopEvery :: Int -> IO () -> IO ()
    loopEvery i func = do
        func
        threadDelay $ i * 1000 * 1000
        loopEvery i func

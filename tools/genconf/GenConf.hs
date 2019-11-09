{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}

module GenConf where

import Control.Lens

import Data.Maybe
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as T
import qualified Data.Yaml as Y

import System.Exit
import System.IO
import System.Directory
import System.Process

-- chainweb imports
import Chainweb.Chainweb
import Chainweb.HostAddress
import Chainweb.Mempool.P2pConfig
import Chainweb.Miner.Config
import Chainweb.NodeId
import Chainweb.Utils
import Chainweb.Version

import P2P.Node.Configuration
import P2P.Peer

-- three items to ask the user
-- 1) ask for their hostname (or public ip address)
-- 2) ask for a usable port number (test to see if this is actually open)
-- 3) ask if they want mining coordination turned (the default for this value is yes)

getUserInput ::
     Show b
  => String
  -> Maybe b
  -> (Text -> IO (Maybe b))
  -> Maybe (b -> Either String b)
  -> IO b
getUserInput prompt defaultVal parse safetyCheck = do
    putStr (prompt <> " ")
    hFlush stdout
    input' <- T.getLine
    if T.null input' && isJust defaultVal
      then return $ fromJust defaultVal
      else do
       p <- parse input'
       case p of
         Nothing -> do
           putStrLn "Invalid Input, try again"
           hFlush stdout
           getUserInput prompt defaultVal parse safetyCheck
         Just y -> case safetyCheck of
           Nothing -> return y
           Just f -> case f y of
             Left err -> do
               putStrLn err
               hFlush stdout
               getUserInput prompt defaultVal parse safetyCheck
             Right y' -> return y'

validate :: (a -> Bool) -> String -> Maybe (a -> Either String a)
validate f msg = Just $ \a -> if f a then Right a else Left msg

getConf :: IO ChainwebConfiguration
getConf = do
    ip <- getIP
    hostname <- hostnameFromText ip
    host <- getUserInput (hostMsg ip) (Just hostname) (const $ return Nothing) Nothing
    port <- getUserInput portMsg (Just 443) (return . portFromText) Nothing
    miningCord <- getUserInput mineCoordMsg (Just True) (return . yesorno2Bool) Nothing
    return ChainwebConfiguration
      { _configChainwebVersion = Mainnet01
      , _configNodeId = NodeId 0 -- FIXME
      , _configMiner = EnableConfig False defaultMinerConfig
      , _configCoordinator = miningCord
      , _configHeaderStream = False
      , _configReintroTxs = True
      , _configP2p = defaultP2pConfiguration
                     & p2pConfigPeer . peerConfigAddr
                     .~ HostAddress host port
      , _configTransactionIndex = defaultEnableConfig defaultTransactionIndexConfig
      , _configIncludeOrigin = True
      , _configThrottling = defaultThrottlingConfig
      , _configMempoolP2p = defaultEnableConfig defaultMempoolP2pConfig
      , _configPruneChainDatabase = True
      , _configBlockGasLimit = 100000
      , _configCutFetchTimeout = 3000000
      }
  where
    hostMsg ip = "What is your publicly reachable domain name / IP address (default: " <> T.unpack ip <> ")?"
    portMsg = "Which port would you like to use (default: 443)?"
    mineCoordMsg = "Would you like to turn mining coordination (default: yes)?"

-- This was not exported by the Chainweb.Chainweb module
defaultThrottlingConfig :: ThrottlingConfig
defaultThrottlingConfig = ThrottlingConfig
  { _throttlingRate = 50 -- per second
  , _throttlingMiningRate = 2  -- per second
  , _throttlingPeerRate = 11  -- per second, on for each p2p network
  , _throttlingLocalRate = 0.1 -- per 10 seconds
  }

main :: IO ()
main = do
    conf <- getConf
    exist <- doesFileExist defaultfile
    case exist of
      True ->
        getUserInput msg (Just True) (return . yesorno2Bool) Nothing >>= \case
          True -> writeStuff conf
          False -> putStrLn "Not writing configuration file"
      False -> writeStuff conf
    exitSuccess
  where
    msg = "Would you like to write the configuration to " <> defaultfile <> "?"
    defaultfile = "mainnet.yaml"
    writeStuff c = do
        Y.encodeFile defaultfile c
        putStrLn ("Writing (possibly overwriting) configuration to file " <> defaultfile)

yesorno2Bool :: Text -> Maybe Bool
yesorno2Bool text =
  case T.toLower text of
    "yes" -> Just True
    "no" -> Just False
    _ -> Nothing

checkIP :: Text -> IO (Maybe Hostname)
checkIP ip = do
    value <- getIP
    if value == ip
      then return $ hostnameFromText ip
      else return Nothing

getIP :: IO Text
getIP = T.pack . (read @String) <$> readProcess "dig" (words "TXT +short o-o.myaddr.l.google.com @ns1.google.com") ""
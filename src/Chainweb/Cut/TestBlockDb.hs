-- |
-- Module: Chainweb.Cut.TestBlockDb
-- Copyright: Copyright © 2020 Kadena LLC.
-- License: MIT
-- Maintainer: Stuart Popejoy
--
-- Maintains block header and payload dbs alongside a current cut.
--

module Chainweb.Cut.TestBlockDb
  ( TestBlockDb(..)
  , withTestBlockDb
  , mkTestBlockDb
  , addTestBlockDb
  , getParentTestBlockDb
  ) where

import Control.Concurrent.MVar
import Data.Bifunctor (first)
import qualified Data.HashMap.Strict as HM
import Data.Tuple.Strict (T2(..))

import Chainweb.BlockHeader
import Chainweb.ChainId
import Chainweb.Cut
import Chainweb.Cut.Test
import Chainweb.Payload
import Chainweb.Payload.PayloadStore
import Chainweb.Payload.PayloadStore.RocksDB
import Chainweb.Utils
import Chainweb.Version
import Chainweb.WebBlockHeaderDB

import Data.CAS
import Data.CAS.RocksDB

data TestBlockDb = TestBlockDb
  { _bdbWebBlockHeaderDb :: WebBlockHeaderDb
  , _bdbPayloadDb :: PayloadDb RocksDbCas
  , _bdbCut :: MVar Cut
  }

-- | Initialize TestBlockDb.
withTestBlockDb :: ChainwebVersion -> (TestBlockDb -> IO a) -> IO a
withTestBlockDb cv a = do
  withTempRocksDb "TestBlockDb" $ \rdb -> do
    bdb <- mkTestBlockDb cv rdb
    a bdb

-- | Initialize TestBlockDb.
mkTestBlockDb :: ChainwebVersion -> RocksDb -> IO TestBlockDb
mkTestBlockDb cv rdb = do
    wdb <- initWebBlockHeaderDb rdb cv
    let pdb = newPayloadDb rdb
    initializePayloadDb cv pdb
    initCut <- newMVar $ genesisCut cv
    return $! TestBlockDb wdb pdb initCut

-- | Add a block.
addTestBlockDb :: TestBlockDb -> Nonce -> GenBlockTime -> ChainId -> PayloadWithOutputs -> IO ()
addTestBlockDb (TestBlockDb wdb pdb cmv) n gbt cid outs = do
  c <- takeMVar cmv
  r <- testMine' wdb n gbt (_payloadWithOutputsPayloadHash outs) cid c
  (T2 _ c') <- fromEitherM $ first (userError . show) $ r
  casInsert pdb outs
  putMVar cmv c'

-- | Get header for chain on current cut.
getParentTestBlockDb :: TestBlockDb -> ChainId -> IO BlockHeader
getParentTestBlockDb (TestBlockDb _ _ cmv) cid = do
  c <- readMVar cmv
  fromMaybeM (userError $ "Internal error, parent not found for cid " ++ show cid) $
    HM.lookup cid $ _cutMap c

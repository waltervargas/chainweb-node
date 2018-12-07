{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE CPP #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE ExistentialQuantification #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE OverloadedLists #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE UndecidableInstances #-}

-- |
-- Module: Chainweb.Utils.API
-- Copyright: Copyright © 2018 Kadena LLC.
-- License: MIT
-- Maintainer: Lars Kuhtz <lars@kadena.io>
-- Stability: experimental
--
-- Utils for Chainweb REST APIs
--
module Chainweb.RestAPI.Utils
(
-- * Servant Utils
  Reassoc

-- * API Version
, Version
, ApiVersion(..)
, apiVersion
, prettyApiVersion

-- * Paging
, type PageParams
, type LimitParam
, type NextParam

-- * Chainweb API Endpoints
, ChainwebEndpoint(..)
, NetworkEndpoint(..)
, ChainEndpoint
, CutEndpoint

-- * Some API
--
-- $someapi
, SomeApi(..)
, someApi

-- ** Some Server
, SomeServer(..)
, someServerApplication

) where

import Data.Aeson
import Data.Kind
import Data.Proxy
import qualified Data.Text as T

import GHC.Generics
import GHC.TypeLits

import Servant.API
import Servant.Client
import Servant.Server
import Servant.Swagger

-- internal modules

import Chainweb.ChainId
import Chainweb.RestAPI.NetworkID
import Chainweb.RestAPI.Orphans ()
import Chainweb.Utils.Paging hiding (properties)
import Chainweb.Version

-- -------------------------------------------------------------------------- --
-- Servant Utils

type Reassoc (api :: Type) = ReassocBranch api '[]

type family ReassocBranch (a :: s) (b :: [Type]) :: Type where
    ReassocBranch (a :> b) rest = ReassocBranch a (b ': rest)
    ReassocBranch a '[] = a
    ReassocBranch a (b ': rest) = a :> ReassocBranch b rest

-- -------------------------------------------------------------------------- --
-- API Version

type Version = "0.0"

newtype ApiVersion = ApiVersion T.Text
    deriving (Show, Eq, Ord, Generic)
    deriving newtype (ToJSON, FromJSON, FromHttpApiData)

apiVersion :: ApiVersion
apiVersion = ApiVersion . T.pack $ symbolVal (Proxy @Version)

prettyApiVersion :: T.Text
prettyApiVersion = case apiVersion of
    ApiVersion t -> t

-- -------------------------------------------------------------------------- --
-- Paging Utils

-- | Pages Parameters
--
-- *   limit :: Natural
-- *   next :: k
--
type PageParams k = LimitParam :> NextParam k

type LimitParam = QueryParam "limit" Limit
type NextParam k = QueryParam "next" k

-- -------------------------------------------------------------------------- --
-- Chainweb API Endpoints

newtype ChainwebEndpoint = ChainwebEndpoint ChainwebVersionT

type ChainwebEndpointApi c a = "chainweb" :> Version :> ChainwebVersionSymbol c :> a

instance
    (HasServer api ctx, KnownChainwebVersionSymbol c)
    => HasServer ('ChainwebEndpoint c :> api) ctx
  where
    type ServerT ('ChainwebEndpoint c :> api) m
        = ServerT (ChainwebEndpointApi c api) m

    route _ = route $ Proxy @(ChainwebEndpointApi c api)

    hoistServerWithContext _ = hoistServerWithContext
        $ Proxy @(ChainwebEndpointApi c api)

instance
    (KnownChainwebVersionSymbol c, HasSwagger api)
    => HasSwagger ('ChainwebEndpoint c :> api)
  where
    toSwagger _ = toSwagger (Proxy @(ChainwebEndpointApi c api))

instance
    (KnownChainwebVersionSymbol v, HasClient m api)
    => HasClient m ('ChainwebEndpoint v :> api)
  where
    type Client m ('ChainwebEndpoint v :> api)
        = Client m (NetworkEndpointApi 'CutNetworkT api)

    clientWithRoute pm _
        = clientWithRoute pm $ Proxy @(ChainwebEndpointApi v api)
    hoistClientMonad pm _
        = hoistClientMonad pm $ Proxy @(ChainwebEndpointApi v api)

-- -------------------------------------------------------------------------- --
-- Network API Endpoint

newtype NetworkEndpoint = NetworkEndpoint NetworkIdT

type ChainEndpoint (c :: ChainIdT) = 'NetworkEndpoint ('ChainNetworkT c)
type CutEndpoint = 'NetworkEndpoint 'CutNetworkT

type family NetworkEndpointApi (net :: NetworkIdT) (api :: Type) :: Type where
    NetworkEndpointApi 'CutNetworkT api = "cut" :> api
    NetworkEndpointApi ('ChainNetworkT c) api = "chain" :> ChainIdSymbol c :> api

-- HasServer

instance
    (HasServer api ctx, KnownChainIdSymbol c, x ~ 'ChainNetworkT c)
    => HasServer ('NetworkEndpoint ('ChainNetworkT c) :> api) ctx
  where
    type ServerT ('NetworkEndpoint ('ChainNetworkT c) :> api) m
        = ServerT (NetworkEndpointApi ('ChainNetworkT c) api) m

    route _ = route (Proxy @(NetworkEndpointApi x api))

    hoistServerWithContext _ = hoistServerWithContext
        (Proxy @(NetworkEndpointApi x api))

instance
    HasServer api ctx => HasServer ('NetworkEndpoint 'CutNetworkT :> api) ctx
  where
    type ServerT ('NetworkEndpoint 'CutNetworkT :> api) m
        = ServerT (NetworkEndpointApi 'CutNetworkT api) m

    route _ = route (Proxy @(NetworkEndpointApi 'CutNetworkT api))

    hoistServerWithContext _ = hoistServerWithContext
        (Proxy @(NetworkEndpointApi 'CutNetworkT api))

-- HasSwagger

instance
    (KnownChainIdSymbol c, HasSwagger api)
    => HasSwagger ('NetworkEndpoint ('ChainNetworkT c) :> api)
  where
    toSwagger _ = toSwagger (Proxy @(NetworkEndpointApi ('ChainNetworkT c) api))

instance
    (HasSwagger api) => HasSwagger ('NetworkEndpoint 'CutNetworkT :> api)
  where
    toSwagger _ = toSwagger (Proxy @(NetworkEndpointApi 'CutNetworkT api))

-- HasClient

instance
    (KnownChainIdSymbol c, HasClient m api)
    => HasClient m ('NetworkEndpoint ('ChainNetworkT c) :> api)
  where
    type Client m ('NetworkEndpoint ('ChainNetworkT c) :> api)
        = Client m (NetworkEndpointApi ('ChainNetworkT c) api)

    clientWithRoute pm _
        = clientWithRoute pm $ Proxy @(NetworkEndpointApi ('ChainNetworkT c) api)
    hoistClientMonad pm _
        = hoistClientMonad pm $ Proxy @(NetworkEndpointApi ('ChainNetworkT c) api)

instance
    (HasClient m api) => HasClient m ('NetworkEndpoint 'CutNetworkT :> api)
  where
    type Client m ('NetworkEndpoint 'CutNetworkT :> api)
        = Client m (NetworkEndpointApi 'CutNetworkT api)

    clientWithRoute pm _
        = clientWithRoute pm $ Proxy @(NetworkEndpointApi 'CutNetworkT api)
    hoistClientMonad pm _
        = hoistClientMonad pm $ Proxy @(NetworkEndpointApi 'CutNetworkT api)

-- -------------------------------------------------------------------------- --
-- Some API

-- $someapi
--
-- The chain graph and thus the list of chain ids is encoded as runtime values.
-- In order to combin these in statically defined APIs we reify the the chainweb
-- version and chainid as types and wrap them existenially so that they can
-- be passed around and be combined.

data SomeApi = forall (a :: Type)
    . (HasSwagger a, HasServer a '[], HasClient ClientM a) => SomeApi (Proxy a)

instance Semigroup SomeApi where
    SomeApi (Proxy :: Proxy a) <> SomeApi (Proxy :: Proxy b)
        = SomeApi (Proxy @(a :<|> b))

instance Monoid SomeApi where
    mappend = (<>)
    mempty = SomeApi (Proxy @EmptyAPI)

someApi
    :: forall proxy (a :: Type)
    . HasServer a '[]
    => HasClient ClientM a
    => HasSwagger a
    => proxy a
    -> SomeApi
someApi _ = SomeApi (Proxy @a)

-- -------------------------------------------------------------------------- --
-- Some API Server

data SomeServer = forall (a :: Type)
    . HasServer a '[] => SomeServer (Proxy a) (Server a)

instance Semigroup SomeServer where
    SomeServer (Proxy :: Proxy a) a <> SomeServer (Proxy :: Proxy b) b
        = SomeServer (Proxy @(a :<|> b)) (a :<|> b)

instance Monoid SomeServer where
    mappend = (<>)
    mempty = SomeServer (Proxy @EmptyAPI) emptyServer

someServerApplication :: SomeServer -> Application
someServerApplication (SomeServer a server) = serve a server

{-|
Module      : Network.AWS.Easy.Service
Description : Configuring and making client connections to AWS services
Copyright   : (C) Richard Cook, 2018
License     : MIT
Maintainer  : rcook@rcook.org
Stability   : experimental
Portability : portable

This module provides support for configuring and making client connections to AWS services using @amazonka@.
-}

{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE CPP #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}

module Amazonka.Easy.Service
    ( AWSConfig
    , Endpoint(..)
    , HostName
    , Logging(..)
    , Port
    , awscCredentials
    , awscEndpoint
    , awscLogging
    , awsConfig
    , connect
    , withAWS
    ) where

import           Control.Lens ((<&>), makeLenses, set)
import           Control.Monad.Trans.AWS
                    ( AWST'
                    , reconfigure
                    , runAWST
                    , within
                    )
import           Data.ByteString (ByteString)
import           Amazonka
                    ( Credentials(..)
                    , Env
                    , LogLevel(..)
                    , Region(..)
                    , Service
                    , envLogger
                    , newEnv
                    , newLogger
                    , runResourceT
                    , setEndpoint
                    )
import           Amazonka.Easy.Classes
import           Amazonka.Easy.Types
import           System.IO (stdout)

#if __GLASGOW_HASKELL__ >= 802
import           Control.Monad.Trans.Control (MonadBaseControl)
import           Control.Monad.Trans.Resource
                    ( MonadUnliftIO
                    , ResourceT
                    )
#else
import           Control.Monad.Trans.Resource
                    ( MonadBaseControl
                    , ResourceT
                    )
#endif

type HostName = ByteString

type Port = Int

data Logging = LoggingEnabled | LoggingDisabled

data Endpoint = AWSRegion Region | Local HostName Port

data AWSConfig = AWSConfig
    { _awscEndpoint :: Endpoint
    , _awscLogging :: Logging
    , _awscCredentials :: Credentials
    }
makeLenses ''AWSConfig

awsConfig :: Endpoint -> AWSConfig
awsConfig endpoint = AWSConfig endpoint LoggingDisabled Discover

connect :: forall a . ServiceClass a => AWSConfig -> a -> IO (TypedSession a)
connect (AWSConfig endpoint logging credentials) service = do
    let serviceRaw = rawService service
    e <- mkEnv logging credentials
    let (r, s) = regionService endpoint serviceRaw
    session' <- return $ Session e r s
    let session = wrappedSession @a session'
    return session

mkEnv :: Logging -> Credentials -> IO Env
-- Standard discovery mechanism for credentials, log to standard output
mkEnv LoggingEnabled c = do
    logger <- newLogger Debug stdout
    newEnv c <&> set envLogger logger
-- Standard discovery mechanism for credentials, no logging
mkEnv LoggingDisabled c = newEnv c

regionService :: Endpoint -> Service -> (Region, Service)
-- Run against a DynamoDB instance running on AWS in specified region
regionService (AWSRegion region) s = (region, s)
-- Run against a local DynamoDB instance on a given host and port
regionService (Local hostName port) s = (NorthVirginia, setEndpoint False hostName port s)

#if __GLASGOW_HASKELL__ >= 802
withAWS :: (MonadBaseControl IO m, MonadUnliftIO m, SessionClass b) =>
#else
withAWS :: (MonadBaseControl IO m, SessionClass b) =>
#endif
    AWST' Env (ResourceT m) a
    -> b
    -> m a
withAWS action session =
    let Session{..} = rawSession session
    in
        runResourceT . runAWST _sEnv . within _sRegion $ do
            reconfigure _sService action

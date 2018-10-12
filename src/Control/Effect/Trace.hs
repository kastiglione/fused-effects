{-# LANGUAGE DeriveFunctor, FlexibleContexts, FlexibleInstances, MultiParamTypeClasses, PolyKinds, TypeOperators, UndecidableInstances #-}
module Control.Effect.Trace
( Trace(..)
, trace
, runPrintingTrace
, PrintingC(..)
, runIgnoringTrace
, IgnoringC(..)
, runReturningTrace
, ReturningC(..)
) where

import Control.Effect.Handler
import Control.Effect.Internal
import Control.Effect.Sum
import Control.Monad.IO.Class
import Data.Bifunctor (first)
import System.IO

data Trace m k = Trace String k
  deriving (Functor)

instance HFunctor Trace where
  hfmap _ (Trace s k) = Trace s k

instance Effect Trace where
  handle state handler (Trace s k) = Trace s (handler (k <$ state))

-- | Append a message to the trace log.
trace :: (Member Trace sig, Carrier sig m) => String -> m ()
trace message = send (Trace message (gen ()))


-- | Run a 'Trace' effect, printing traces to 'stderr'.
runPrintingTrace :: (MonadIO m, Carrier sig m) => Eff (PrintingC m) a -> m a
runPrintingTrace = runPrintingC . interpret

newtype PrintingC m a = PrintingC { runPrintingC :: m a }

instance (MonadIO m, Carrier sig m) => Carrier (Trace :+: sig) (PrintingC m) where
  gen = PrintingC . gen
  alg = algT \/ (PrintingC . alg . handlePure runPrintingC)
    where algT (Trace s k) = PrintingC (liftIO (hPutStrLn stderr s) *> runPrintingC k)


-- | Run a 'Trace' effect, ignoring all traces.
--
--   prop> run (runIgnoringTrace (trace a *> pure b)) == b
runIgnoringTrace :: Carrier sig m => Eff (IgnoringC m) a -> m a
runIgnoringTrace = runIgnoringC . interpret

newtype IgnoringC m a = IgnoringC { runIgnoringC :: m a }

instance Carrier sig m => Carrier (Trace :+: sig) (IgnoringC m) where
  gen = IgnoringC . gen
  alg = algT \/ (IgnoringC . alg . handlePure runIgnoringC)
    where algT (Trace _ k) = k


-- | Run a 'Trace' effect, returning all traces as a list.
--
--   prop> run (runReturningTrace (trace a *> trace b *> pure c)) == ([a, b], c)
runReturningTrace :: Effectful sig m => Eff (ReturningC m) a -> m ([String], a)
runReturningTrace = fmap (first reverse) . flip runReturningC [] . interpret

newtype ReturningC m a = ReturningC { runReturningC :: [String] -> m ([String], a) }

instance (Carrier sig m, Effect sig) => Carrier (Trace :+: sig) (ReturningC m) where
  gen a = ReturningC (\ s -> gen (s, a))
  alg = algT \/ algOther
    where algT (Trace m k) = ReturningC (runReturningC k . (m :))
          algOther op = ReturningC (\ s -> alg (handle (s, ()) (uncurry (flip runReturningC)) op))


-- $setup
-- >>> :seti -XFlexibleContexts
-- >>> import Test.QuickCheck
-- >>> import Control.Effect.Void


-- | Definition of names used in Source Discus language.
module DDC.Source.Discus.Prim.Base
        (
          -- * Primitive Values
          PrimVal       (..)

          -- ** Primitive arithmetic operators.
        , PrimArith     (..)

          -- ** Primitive casting operators.
        , PrimCast      (..)

          -- ** Primitive vector operators.
        , OpVector      (..)

          -- ** Primitive function operators.
        , OpFun         (..)

          -- ** Primitive error handling.
        , OpError       (..)

          -- ** Primitive literals.
        , PrimLit       (..)
        , primLitOfLiteral)
where
import DDC.Core.Exp.Literal
import DDC.Core.Discus
        ( OpFun         (..)
        , OpVector      (..)
        , OpError       (..)
        , PrimArith     (..)
        , PrimCast      (..))

import Data.Text        (Text)


---------------------------------------------------------------------------------------------------
-- | Primitive values.
data PrimVal
        -- | Primitive literals.
        = PrimValLit            !PrimLit

        -- | Primitive arithmetic operators.
        | PrimValArith          !PrimArith

        -- | Primitive numeric casting operators.
        | PrimValCast           !PrimCast

        -- | Primitive error handling.
        | PrimValError          !OpError

        -- | Primitive vector operators.
        | PrimValVector         !OpVector

        -- | Primitive function operators.
        | PrimValFun            !OpFun
        deriving (Eq, Ord, Show)


---------------------------------------------------------------------------------------------------
data PrimLit
        -- | A boolean literal.
        = PrimLitBool           !Bool

        -- | A natural literal,
        --   with enough precision to count every heap object.
        | PrimLitNat            !Integer

        -- | An integer literal,
        --   with enough precision to count every heap object.
        | PrimLitInt            !Integer

        -- | An unsigned size literal,
        --   with enough precision to count every addressable byte of memory.
        | PrimLitSize           !Integer

        -- | A word literal,
        --   with the given number of bits precison.
        | PrimLitWord           !Integer !Int

        -- | A floating point literal,
        --   with the given number of bits precision.
        | PrimLitFloat          !Double !Int

        -- | A character literal.
        | PrimLitChar           !Char

        -- | Text literals (UTF-8 encoded)
        | PrimLitTextLit        !Text
        deriving (Eq, Ord, Show)


-- | Convert a literal to a Discus name.
primLitOfLiteral :: Literal -> Maybe PrimLit
primLitOfLiteral lit
 = case lit of
        LNat    n               -> Just $ PrimLitNat     n
        LInt    i               -> Just $ PrimLitInt     i
        LSize   s               -> Just $ PrimLitSize    s
        LWord   i b             -> Just $ PrimLitWord    i b

        LFloat  f (Just 32)     -> Just $ PrimLitFloat   f 32
        LFloat  f (Just 64)     -> Just $ PrimLitFloat   f 64
        LFloat  f Nothing       -> Just $ PrimLitFloat   f 64

        LChar   c               -> Just $ PrimLitChar    c
        LString tx              -> Just $ PrimLitTextLit tx

        _                       -> Nothing


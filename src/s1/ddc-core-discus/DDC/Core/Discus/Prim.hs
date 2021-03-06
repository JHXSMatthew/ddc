
module DDC.Core.Discus.Prim
        ( -- * Names and lexing.
          Name          (..)
        , isNameHole
        , isNameLit
        , isNameLitUnboxed
        , readName
        , takeTypeOfLitName
        , takeTypeOfPrimOpName

          -- * Baked-in type constructors.
        , TyConDiscus     (..)
        , readTyConDiscus
        , kindTyConDiscus
        , tTupleN, tUnboxed, tFunValue, tTextLit

          -- * Baked-in data constructors.
        , DaConDiscus     (..)
        , readDaConDiscus
        , typeDaConDiscus

          -- * Baked-in function operators.
        , OpFun         (..)
        , readOpFun
        , typeOpFun

          -- * Baked-in vector operators.
        , OpVector      (..)
        , readOpVectorFlag
        , typeOpVectorFlag

          -- * Baked-in info table operators.
        , OpInfo        (..)
        , readOpInfoFlag
        , typeOpInfoFlag

          --- * Baked-in error handling.
        , OpError       (..)
        , readOpErrorFlag
        , typeOpErrorFlag

          -- * Primitive type constructors.
        , PrimTyCon     (..)
        , pprPrimTyConStem
        , readPrimTyCon,        readPrimTyConStem
        , kindPrimTyCon

          -- * Primitive arithmetic operators.
        , PrimArith     (..)
        , readPrimArithFlag
        , typePrimArithFlag

          -- * Primitive numeric casts.
        , PrimCast      (..)
        , readPrimCastFlag
        , typePrimCastFlag)
where
import DDC.Core.Discus.Prim.Base
import DDC.Core.Discus.Prim.TyConDiscus
import DDC.Core.Discus.Prim.TyConPrim
import DDC.Core.Discus.Prim.DaConDiscus
import DDC.Core.Discus.Prim.OpError
import DDC.Core.Discus.Prim.OpArith
import DDC.Core.Discus.Prim.OpCast
import DDC.Core.Discus.Prim.OpFun
import DDC.Core.Discus.Prim.OpVector
import DDC.Core.Discus.Prim.OpInfo
import DDC.Type.Exp
import DDC.Data.Pretty
import DDC.Data.Name
import Control.DeepSeq
import Data.Char
import qualified Data.Text              as T
import Data.Text                        (Text)

import DDC.Core.Codec.Text.Lexer.Tokens            (isVarStart)

import DDC.Core.Salt.Name
        ( readLitNat
        , readLitInt
        , readLitWordOfBits)

instance NFData Name where
 rnf nn
  = case nn of
        NameVar s               -> rnf s
        NameCon s               -> rnf s
        NameExt n s             -> rnf n `seq` rnf s

        NameTyConDiscus con     -> rnf con
        NameDaConDiscus con     -> rnf con

        NameOpError    op !_    -> rnf op
        NameOpFun      op       -> rnf op
        NameOpVector   op !_    -> rnf op
        NameOpInfo     op !_    -> rnf op

        NamePrimTyCon  op       -> rnf op
        NamePrimArith  op !_    -> rnf op
        NamePrimCast   op !_    -> rnf op

        NameLitBool    b        -> rnf b
        NameLitNat     n        -> rnf n
        NameLitInt     i        -> rnf i
        NameLitSize    s        -> rnf s
        NameLitWord    i bits   -> rnf i `seq` rnf bits
        NameLitFloat   d bits   -> rnf d `seq` rnf bits
        NameLitChar    c        -> rnf c
        NameLitTextLit bs       -> rnf bs

        NameLitUnboxed n        -> rnf n

        NameHole                -> ()


instance Pretty Name where
 ppr nn
  = case nn of
        NameVar  v              -> text v
        NameCon  c              -> text c
        NameExt  n s            -> ppr n <> text "$" <> text s

        NameTyConDiscus tc      -> ppr tc
        NameDaConDiscus dc      -> ppr dc

        NameOpError    op False -> ppr op
        NameOpError    op True  -> ppr op <> text "#"

        NameOpFun      op       -> ppr op

        NameOpVector   op False -> ppr op
        NameOpVector   op True  -> ppr op <> text "#"

        NameOpInfo     op False -> ppr op
        NameOpInfo     op True  -> ppr op <> text "#"

        NamePrimTyCon  op       -> ppr op

        NamePrimArith  op False -> ppr op
        NamePrimArith  op True  -> ppr op <> text "#"

        NamePrimCast   op False -> ppr op
        NamePrimCast   op True  -> ppr op <> text "#"

        NameLitBool    True     -> text "True#"
        NameLitBool    False    -> text "False#"
        NameLitNat     i        -> integer i                            <> text "#"
        NameLitInt     i        -> integer i <> text "i"                <> text "#"
        NameLitSize    s        -> integer s <> text "s"                <> text "#"
        NameLitWord    i bits   -> integer i <> text "w" <> int bits    <> text "#"
        NameLitFloat   f bits   -> double  f <> text "f" <> int bits    <> text "#"
        NameLitChar    c        -> string (show c)                      <> text "#"
        NameLitTextLit tx       -> string (show $ T.unpack tx)          <> text "#"

        NameLitUnboxed n        -> ppr n <> text "#"

        NameHole                -> text "?"


instance CompoundName Name where
 extendName n str
  = NameExt n $ T.pack str

 newVarName str
  = NameVar $ T.pack str

 splitName nn
  = case nn of
        NameExt n str    -> Just (n, T.unpack str)
        _                -> Nothing


-- | Read the name of a variable, constructor or literal.
readName :: Text -> Maybe Name
readName str
        -- Baked-in names.
        | Just p        <- readTyConDiscus   $ T.unpack str
        = Just $ NameTyConDiscus p

        | Just p        <- readDaConDiscus   $ T.unpack str
        = Just $ NameDaConDiscus p

        | Just (p,f)    <- readOpErrorFlag   $ T.unpack str
        = Just $ NameOpError p f

        | Just p        <- readOpFun         $ T.unpack str
        = Just $ NameOpFun p

        | Just (p, f)   <- readOpVectorFlag  $ T.unpack str
        = Just $ NameOpVector p f

        | Just (p, f)   <- readOpInfoFlag    $ T.unpack str
        = Just $ NameOpInfo p f

        -- Primitive names.
        | Just p        <- readPrimTyCon     $ T.unpack str
        = Just $ NamePrimTyCon p

        | Just (p, f)   <- readPrimArithFlag $ T.unpack str
        = Just $ NamePrimArith p f

        | Just (p, f)   <- readPrimCastFlag  $ T.unpack str
        = Just $ NamePrimCast  p f

        -- Literal Bools
        | str == "True"  = Just $ NameLitBool True
        | str == "False" = Just $ NameLitBool False

        -- Literal Nat
        | Just val      <- readLitNat $ T.unpack str
        = Just $ NameLitNat  val

        -- Literal Ints
        | Just val      <- readLitInt $ T.unpack str
        = Just $ NameLitInt  val

        -- Literal Words
        | Just (val, bits) <- readLitWordOfBits $ T.unpack str
        , elem bits [8, 16, 32, 64]
        = Just $ NameLitWord val bits

        -- Unboxed literals.
        | Just base     <- T.stripSuffix "#" str
        , Just n        <- readName base
        = case n of
                NameLitBool{}   -> Just n
                NameLitNat{}    -> Just n
                NameLitInt{}    -> Just n
                NameLitWord{}   -> Just n
                _               -> Nothing

        -- Holes
        | str == "?"
        = Just $ NameHole

        -- Constructors.
        | Just (c, _)   <- T.uncons str
        , isUpper c
        = Just $ NameCon str

        -- Variables.
        | Just (c, _)   <- T.uncons str
        , isVarStart c
        = Just $ NameVar str

        | otherwise
        = Nothing


-- | Get the type associated with a literal name.
takeTypeOfLitName :: Name -> Maybe (Type Name)
takeTypeOfLitName nn
 = case nn of
        NameLitBool{}           -> Just tBool
        NameLitNat{}            -> Just tNat
        NameLitInt{}            -> Just tInt
        NameLitWord _ bits      -> Just (tWord  bits)
        NameLitFloat _ bits     -> Just (tFloat bits)
        NameLitChar _           -> Just (tWord  32)     -- TODO: char wants its own type.
        NameLitTextLit _        -> Just tTextLit
        _                       -> Nothing


-- | Take the type of a primitive operator.
takeTypeOfPrimOpName :: Name -> Maybe (Type Name)
takeTypeOfPrimOpName nn
 = case nn of
        NameOpError     op f    -> Just (typeOpErrorFlag   op f)
        NameOpFun       op      -> Just (typeOpFun         op)
        NameOpVector    op f    -> Just (typeOpVectorFlag  op f)
        NameOpInfo      op f    -> Just (typeOpInfoFlag    op f)
        NamePrimArith   op f    -> Just (typePrimArithFlag op f)
        NamePrimCast    op f    -> Just (typePrimCastFlag  op f)
        _                       -> Nothing


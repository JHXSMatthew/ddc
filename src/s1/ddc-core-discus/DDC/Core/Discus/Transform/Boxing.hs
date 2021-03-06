
module DDC.Core.Discus.Transform.Boxing
        (boxingModule)
where
import DDC.Core.Discus.Compounds
import DDC.Core.Discus.Prim
import DDC.Core.Module
import DDC.Core.Transform.Boxing           (Rep(..), Config(..))
import qualified DDC.Core.Transform.Boxing as Boxing


-- | Manage boxing of numeric values in a module.
boxingModule :: Show a => Module a Name -> Module a Name
boxingModule mm
 = let
        tsForeignSea
         = [ (n, t) | (n, ImportValueSea _ _ _ t) <- moduleImportValues mm]

   in   Boxing.boxingModule (config tsForeignSea) mm


-- | Discus-specific configuration for boxing transform.
config :: [(Name, Type Name)] -> Config a Name
config ntsForeignSea
        = Config
        { configRepOfType               = repOfType
        , configConvertRepType          = convertRepType
        , configConvertRepExp           = convertRepExp
        , configValueTypeOfLitName      = takeTypeOfLitName
        , configValueTypeOfPrimOpName   = takeTypeOfPrimOpName
        , configValueTypeOfForeignName  = \n -> lookup n ntsForeignSea
        , configUnboxPrimOpName         = unboxPrimOpName
        , configUnboxLitName            = unboxLitName }


-- | Get the representation of a given type.
repOfType :: Type Name -> Maybe Rep
repOfType tt
        -- These types are listed out in full so anyone who adds more
        -- constructors to the PrimTyCon type is forced to specify what
        -- the representation is.
        | Just (NamePrimTyCon n, _)     <- takeNameTyConApps tt
        = case n of
                PrimTyConVoid           -> Just RepNone

                PrimTyConBool           -> Just RepBoxed
                PrimTyConNat            -> Just RepBoxed
                PrimTyConInt            -> Just RepBoxed
                PrimTyConSize           -> Just RepBoxed
                PrimTyConWord{}         -> Just RepBoxed
                PrimTyConFloat{}        -> Just RepBoxed
                PrimTyConVec{}          -> Just RepBoxed
                PrimTyConAddr{}         -> Just RepBoxed
                PrimTyConPtr{}          -> Just RepBoxed
                PrimTyConTextLit{}      -> Just RepBoxed
                PrimTyConTag{}          -> Just RepBoxed

        -- Explicitly unboxed things.
        | Just (n, _)   <- takeNameTyConApps tt
        , NameTyConDiscus TyConDiscusU    <- n
        = Just RepUnboxed

        | Just (NameTyConDiscus n, _)    <- takeNameTyConApps tt
        = case n of
                -- These are all higher-kinded type constructors,
                -- which don't have any associated values.
                TyConDiscusTuple{}       -> Just RepNone
                TyConDiscusVector{}      -> Just RepNone
                TyConDiscusU{}           -> Just RepNone
                TyConDiscusF{}           -> Just RepNone


        | otherwise
        = Nothing


-- | Get the type for a different representation of the given one.
convertRepType :: Rep -> Type Name -> Maybe (Type Name)
convertRepType RepBoxed tt
        -- Produce the value type from an unboxed one.
        | Just (n, [t]) <- takeNameTyConApps tt
        , NameTyConDiscus TyConDiscusU    <- n
        = Just t

convertRepType RepUnboxed tt
        | Just (NamePrimTyCon tc, [])   <- takeNameTyConApps tt
        = case tc of
                PrimTyConBool           -> Just $ tUnboxed tBool
                PrimTyConNat            -> Just $ tUnboxed tNat
                PrimTyConInt            -> Just $ tUnboxed tInt
                PrimTyConSize           -> Just $ tUnboxed tSize
                PrimTyConAddr           -> Just $ tUnboxed tAddr
                PrimTyConWord  bits     -> Just $ tUnboxed (tWord  bits)
                PrimTyConFloat bits     -> Just $ tUnboxed (tFloat bits)
                PrimTyConTextLit        -> Just $ tUnboxed tTextLit
                _                       -> Nothing

        | Just (NameTyConDiscus tc, [])   <- takeNameTyConApps tt
        = case tc of
                _                       -> Nothing

convertRepType _ _
        = Nothing


-- | Convert an expression from one representation to another.
convertRepExp :: Rep -> a -> Type Name -> Exp a Name -> Maybe (Exp a Name)
convertRepExp rep a tSource xx
        | Just tResult  <- convertRepType rep tSource
        = Just $ xCastConvert a tSource tResult xx

        | otherwise
        = Nothing


-- | Convert a primitive operator name to the unboxed version.
unboxPrimOpName :: Name -> Maybe Name
unboxPrimOpName n
 = case n of
        NamePrimArith op False  -> Just $ NamePrimArith op True
        NamePrimCast  op False  -> Just $ NamePrimCast  op True
        NameOpVector  op False  -> Just $ NameOpVector  op True
        NameOpError   op False  -> Just $ NameOpError   op True
        NameOpInfo    op False  -> Just $ NameOpInfo    op True
        _                       -> Nothing


-- | If this is the name of an literal, then produce the unboxed version.
unboxLitName :: Name -> Maybe Name
unboxLitName n
        | isNameLit n && not (isNameLitUnboxed n)
        = Just $ NameLitUnboxed n

        | otherwise
        = Nothing

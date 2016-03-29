
module DDC.Core.Salt.Compounds.PrimTyCon
        ( rTop,  ukTop

        , tVoid, tBool, tNat, tInt, tSize, tWord, tFloat
        , tAddr
        , tPtr,  takeTPtr
        , tTextLit
        , tTag

        , tObj)
where
import DDC.Core.Salt.Name
import DDC.Core.Exp
import DDC.Core.Compounds


-- Regions --------------------------------------------------------------------
-- | The top-level region.
--   This region lives for the whole program, and is used to store objects whose 
--   types don't have region annotations (like function closures and Unit values).
rTop    :: Type Name
rTop   = TVar (fst ukTop)

ukTop :: (Bound Name, Kind Name)
ukTop
 =      ( UName (NameVar "rT")
        , kRegion)


-- Types ----------------------------------------------------------------------
tVoid, tBool, tNat, tInt, tSize, tTag, tAddr, tTextLit :: Type Name
tVoid     = TCon (TyConBound (UPrim (NamePrimTyCon PrimTyConVoid)    kData) kData)
tBool     = TCon (TyConBound (UPrim (NamePrimTyCon PrimTyConBool)    kData) kData)
tNat      = TCon (TyConBound (UPrim (NamePrimTyCon PrimTyConNat)     kData) kData)
tInt      = TCon (TyConBound (UPrim (NamePrimTyCon PrimTyConInt)     kData) kData)
tSize     = TCon (TyConBound (UPrim (NamePrimTyCon PrimTyConSize)    kData) kData)
tAddr     = TCon (TyConBound (UPrim (NamePrimTyCon PrimTyConAddr)    kData) kData)
tTag      = TCon (TyConBound (UPrim (NamePrimTyCon PrimTyConTag)     kData) kData)
tTextLit  = TCon (TyConBound (UPrim (NamePrimTyCon PrimTyConTextLit) kData) kData)


tWord :: Int -> Type Name
tWord bits = TCon (TyConBound (UPrim (NamePrimTyCon (PrimTyConWord bits)) kData) kData)


tFloat :: Int -> Type Name
tFloat bits = TCon (TyConBound (UPrim (NamePrimTyCon (PrimTyConFloat bits)) kData) kData)


tObj :: Type Name
tObj      = TCon (TyConBound (UPrim  NameObjTyCon kData) kData)


-- Pointer
tPtr :: Region Name -> Type Name -> Type Name
tPtr r t = TApp (TApp (TCon tcPtr) r) t
 where  tcPtr   = TyConBound (UPrim (NamePrimTyCon PrimTyConPtr) kPtr) kPtr
        kPtr    = kRegion `kFun` kData `kFun` kData

takeTPtr :: Type Name -> Maybe (Region Name, Type Name)
takeTPtr tt
 = case tt of
        TApp (TApp (TCon tc) r) t
         | TyConBound (UPrim (NamePrimTyCon PrimTyConPtr) _) _  <- tc
         -> Just (r, t)

        _ -> Nothing

